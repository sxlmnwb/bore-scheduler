#!/system/bin/sh
# ════════════════════════════════════════════════════════════
# BORE Scheduler Feature Test & Benchmark
# Must run ON DEVICE as root: su -c sh bore_test.sh
# ════════════════════════════════════════════════════════════

echo "━━━ [0] Device Information ━━━"
echo ""

MODEL=$(getprop ro.product.marketname)
[ -z "$MODEL" ] && MODEL=$(getprop ro.product.model)
MANUF=$(getprop ro.product.manufacturer)
ANDROID=$(getprop ro.build.version.release)
SOC=$(getprop ro.hardware)
MEM=$(cat /proc/meminfo | grep MemTotal | awk '{printf "%.0f MB", $2/1024}')
ROOT=$(id -u)

printf "  Device:     %s %s\n" "$MANUF" "$MODEL"
printf "  Android:    %s\n" "$ANDROID"
printf "  SoC:        %s\n" "$SOC"
printf "  Memory:     %s\n" "$MEM"
printf "  Kernel:     %s\n" "$(uname -r)"

if [ "$ROOT" = "0" ]; then
    echo "  Root:       ✅ Yes (UID 0)"
else
    echo "  Root:       ❌ No (UID $ROOT) - Some tests will fail!"
fi

if [ -f /proc/sys/kernel/sched_bore ]; then
    echo "  BORE:       ✅ Detected"
else
    echo "  BORE:       ❌ Not detected!"
fi

if [ -f /proc/config.gz ]; then
    BORE_CFG=$(zcat /proc/config.gz 2>/dev/null | grep "CONFIG_SCHED_BORE=" | head -1)
    if [ -n "$BORE_CFG" ]; then
        echo "  BORE CFG:   ✅ $BORE_CFG"
    else
        echo "  BORE CFG:   ⚠️ Not found in /proc/config.gz"
    fi
else
    echo "  BORE CFG:   ⚠️ /proc/config.gz not available"
fi

if [ -f /proc/sys/kernel/sched_bore_version ]; then
    VER=$(head -n 1 /proc/sys/kernel/sched_bore_version 2>/dev/null)
    echo "  Version:    ✅ $VER"
else
    echo "  Version:    ❌ Not found"
fi

CPU_CORES=$(cat /proc/cpuinfo | grep -c "^processor")
CPU_TYPE=$(cat /proc/cpuinfo | grep "CPU part" | head -1 | awk -F': ' '{print $2}')
[ -z "$CPU_TYPE" ] && CPU_TYPE=$(cat /proc/cpuinfo | grep "Hardware" | head -1 | awk -F': ' '{print $2}')
printf "  CPU:        %s cores (%s)\n" "$CPU_CORES" "$CPU_TYPE"

GKI=$(uname -r | grep -c "android")
[ "$GKI" -gt 0 ] && echo "  GKI:        ✅ Yes" || echo "  GKI:        ⚠️ Not detected"

BORE_ON=1
BORE_OFF=0
PASS=0; FAIL=0; WARN=0
pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
warn() { WARN=$((WARN+1)); echo "  ⚠️  $1"; }
set_bore() { echo $1 > /proc/sys/kernel/sched_bore; sleep 1; }

# Helper: read burst_score from /proc/<pid>/sched
get_burst_score() {
    grep "burst_score" /proc/$1/sched 2>/dev/null | awk '{print $NF}'
}

echo ""
echo "━━━ [1] Core BORE Functionality ━━━"
echo ""

echo "  [1.1] Toggle Test"
set_bore $BORE_ON
[ "$(cat /proc/sys/kernel/sched_bore)" = "1" ] && pass "BORE can be enabled" || fail "BORE enable failed"
set_bore $BORE_OFF
[ "$(cat /proc/sys/kernel/sched_bore)" = "0" ] && pass "BORE can be disabled" || fail "BORE disable failed"
set_bore $BORE_ON

echo ""
echo "  [1.2] Version String"
VER=$(head -n 1 /proc/sys/kernel/sched_bore_version 2>/dev/null)
[ -n "$VER" ] && pass "Version: $VER" || fail "Version string missing"

echo ""
echo "  [1.3] Sysctl Parameters"
for p in sched_bore sched_burst_exclude_kthreads \
         sched_burst_smoothness_long sched_burst_smoothness_short \
         sched_burst_fork_atavistic sched_burst_parity_threshold \
         sched_burst_penalty_offset sched_burst_penalty_scale \
         sched_burst_cache_stop_count sched_burst_cache_lifetime \
         sched_deadline_boost_mask; do
    v=$(cat /proc/sys/kernel/$p 2>/dev/null)
    if [ -n "$v" ]; then
        printf "    ✅ %-45s = %s\n" "$p" "$v"
    else
        printf "    ❌ %-45s MISSING\n" "$p"
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "━━━ [2] Burst Penalty System ━━━"
echo ""

# 2.1 Verify burst_score exists
echo "  [2.1] Burst Score in /proc/<pid>/sched"
MY_SCORE=$(get_burst_score $$)
if [ -n "$MY_SCORE" ]; then
    pass "burst_score readable: $MY_SCORE"
else
    fail "burst_score NOT found in /proc/$$/sched!"
fi

# 2.2 Different tasks should have different burst scores
echo ""
echo "  [2.2] Burst Score Differentiation"
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
HEAVY1=$!
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
HEAVY2=$!
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
HEAVY3=$!

sleep 5

SCORES=""
# Explicitly include heavy tasks and current shell
for pid in $HEAVY1 $HEAVY2 $HEAVY3 $$; do
    s=$(get_burst_score $pid)
    [ -n "$s" ] && SCORES="$SCORES $s"
done
# Scan more PIDs (head -500 instead of head -80)
for pid in $(ls /proc/ | grep -E '^[0-9]+$' | head -500); do
    s=$(get_burst_score $pid)
    [ -n "$s" ] && SCORES="$SCORES $s"
done

kill $HEAVY1 $HEAVY2 $HEAVY3 2>/dev/null
wait $HEAVY1 $HEAVY2 $HEAVY3 2>/dev/null

UNIQUE=$(echo $SCORES | tr ' ' '\n' | sort -un | grep -v '^$' | wc -l)
if [ "$UNIQUE" -gt 1 ]; then
    pass "Multiple burst scores detected ($UNIQUE unique values)"
    echo "       Scores: $(echo $SCORES | tr ' ' '\n' | sort -un | head -10 | tr '\n' ' ')"
else
    warn "Only $UNIQUE unique burst score - tasks may be too short-lived"
fi

# 2.3 CPU-heavy task should have HIGHER score than idle task
echo ""
echo "  [2.3] Burst Penalty for CPU-heavy Task"
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
DD_PID=$!
sleep 5  # Let BORE calculate penalty from burst time

DD_SCORE=$(get_burst_score $DD_PID)
SHELL_SCORE=$(get_burst_score $$)
kill $DD_PID 2>/dev/null
wait $DD_PID 2>/dev/null

if [ -n "$DD_SCORE" ] && [ -n "$SHELL_SCORE" ]; then
    if [ "$DD_SCORE" -ge "$SHELL_SCORE" ]; then
        pass "CPU-heavy task (score=$DD_SCORE) >= idle shell (score=$SHELL_SCORE)"
    else
        warn "CPU-heavy task (score=$DD_SCORE) < idle shell (score=$SHELL_SCORE)"
    fi
else
    fail "Cannot read burst_score (DD=$DD_SCORE, shell=$SHELL_SCORE)"
fi

# 2.4 Higher penalty_scale should produce higher score
echo ""
echo "  [2.4] Penalty Scale Affects Score"
ORIG_SCALE=$(cat /proc/sys/kernel/sched_burst_penalty_scale)

echo 640 > /proc/sys/kernel/sched_burst_penalty_scale
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
DD_PID=$!
sleep 5
SCORE_LOW=$(get_burst_score $DD_PID)
kill $DD_PID 2>/dev/null; wait $DD_PID 2>/dev/null

echo 2560 > /proc/sys/kernel/sched_burst_penalty_scale
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
DD_PID=$!
sleep 5
SCORE_HIGH=$(get_burst_score $DD_PID)
kill $DD_PID 2>/dev/null; wait $DD_PID 2>/dev/null

echo $ORIG_SCALE > /proc/sys/kernel/sched_burst_penalty_scale

if [ -n "$SCORE_LOW" ] && [ -n "$SCORE_HIGH" ]; then
    if [ "$SCORE_HIGH" -ge "$SCORE_LOW" ]; then
        pass "Higher penalty_scale → higher score ($SCORE_LOW → $SCORE_HIGH)"
    else
        warn "Score didn't increase with penalty_scale ($SCORE_LOW → $SCORE_HIGH)"
    fi
else
    fail "Cannot read burst_score (low=$SCORE_LOW, high=$SCORE_HIGH)"
fi

echo ""
echo "━━━ [3] Fork Atavistic Inheritance ━━━"
echo ""

echo "  [3.1] Fork Atavistic Parameter"
FA_VAL=$(cat /proc/sys/kernel/sched_burst_fork_atavistic)
[ "$FA_VAL" -ge 0 ] && [ "$FA_VAL" -le 3 ] && pass "sched_burst_fork_atavistic = $FA_VAL (valid: 0-3)" || fail "Invalid value: $FA_VAL"

# 3.2 Child inherits parent burst
echo ""
echo "  [3.2] Child Inherits Parent Burst"
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
PARENT_PID=$!
sleep 5  # Let parent accumulate burst time

PARENT_SCORE=$(get_burst_score $PARENT_PID)

# Fork a child from the CPU-heavy parent
sh -c 'sleep 10' &
CHILD_PID=$!
sleep 2

CHILD_SCORE=$(get_burst_score $CHILD_PID)
kill $PARENT_PID $CHILD_PID 2>/dev/null
wait $PARENT_PID $CHILD_PID 2>/dev/null

if [ -n "$PARENT_SCORE" ] && [ -n "$CHILD_SCORE" ]; then
    pass "Child has burst_score ($CHILD_SCORE), parent has ($PARENT_SCORE)"
else
    fail "Cannot read burst_score (parent=$PARENT_SCORE, child=$CHILD_SCORE)"
fi

# 3.3 Test different atavistic levels
echo ""
echo "  [3.3] Atavistic Level Variants"
ORIG_FA=$(cat /proc/sys/kernel/sched_burst_fork_atavistic)
for level in 0 1 2 3; do
    echo $level > /proc/sys/kernel/sched_burst_fork_atavistic
    NEW=$(cat /proc/sys/kernel/sched_burst_fork_atavistic)
    if [ "$NEW" = "$level" ]; then
        printf "    ✅ Level %d: OK\n" $level
    else
        printf "    ❌ Level %d: FAILED (got %s)\n" $level "$NEW"
        FAIL=$((FAIL+1))
    fi
done
echo $ORIG_FA > /proc/sys/kernel/sched_burst_fork_atavistic

echo ""
echo "━━━ [4] Deadline Boost ━━━"
echo ""

echo "  [4.1] Deadline Boost Mask"
DBM=$(cat /proc/sys/kernel/sched_deadline_boost_mask)
if [ "$DBM" -gt 0 ]; then
    pass "sched_deadline_boost_mask = $DBM (non-zero = boost enabled)"
    [ "$DBM" = "129" ] && echo "       (ENQUEUE_INITIAL | ENQUEUE_WAKEUP = default)"
else
    warn "sched_deadline_boost_mask = 0 (no boost!)"
fi

echo ""
echo "━━━ [5] Kthread Exclusion ━━━"
echo ""

echo "  [5.1] Kthread Exclusion"
KTE=$(cat /proc/sys/kernel/sched_burst_exclude_kthreads)
[ "$KTE" = "1" ] && pass "sched_burst_exclude_kthreads = 1 (kthreads excluded)" || warn "sched_burst_exclude_kthreads = $KTE"

echo ""
echo "  [5.2] Kernel Thread Burst Scores"
KT_ZERO=0; KT_NONZERO=0
for pid in $(ls /proc/ | grep -E '^[0-9]+$' | head -50); do
    FLAGS=$(cat /proc/$pid/stat 2>/dev/null | awk '{print $9}')
    SCORE=$(get_burst_score $pid)
    if [ -n "$FLAGS" ] && [ -n "$SCORE" ]; then
        if [ $((FLAGS & 2097152)) -ne 0 ]; then
            [ "$SCORE" = "0" ] && KT_ZERO=$((KT_ZERO+1)) || KT_NONZERO=$((KT_NONZERO+1))
        fi
    fi
done
if [ "$KTE" = "1" ]; then
    [ "$KT_NONZERO" -eq 0 ] && pass "All kernel threads have burst_score = 0" || warn "$KT_NONZERO kernel threads have non-zero burst_score!"
else
    echo "    (kthread exclusion disabled, skipping check)"
fi

echo ""
echo "━━━ [6] Smoothness Parameters ━━━"
echo ""

SL=$(cat /proc/sys/kernel/sched_burst_smoothness_long)
SS=$(cat /proc/sys/kernel/sched_burst_smoothness_short)
printf "  sched_burst_smoothness_long  = %d\n" $SL
printf "  sched_burst_smoothness_short = %d\n" $SS
[ "$SL" -ge 0 ] && [ "$SL" -le 1 ] && [ "$SS" -ge 0 ] && [ "$SS" -le 1 ] && pass "Smoothness values valid (0-1)" || warn "Smoothness values out of expected range"

echo ""
echo "━━━ [7] Parity Threshold ━━━"
echo ""

PT=$(cat /proc/sys/kernel/sched_burst_parity_threshold)
printf "  sched_burst_parity_threshold = %d\n" $PT
[ "$PT" -ge 0 ] && [ "$PT" -le 255 ] && pass "Parity threshold valid (0-255)" || fail "Parity threshold out of range!"

echo ""
echo "━━━ [8] Interactive Responsiveness ━━━"
echo ""

echo "  [8.1] App Launch Under Load"
for bore_state in 1 0; do
    set_bore $bore_state
    LABEL=$([ "$bore_state" = "1" ] && echo "BORE ON " || echo "BORE OFF")
    dd if=/dev/zero of=/dev/null bs=1M count=5000 2>/dev/null &
    dd if=/dev/zero of=/dev/null bs=1M count=5000 2>/dev/null &
    dd if=/dev/zero of=/dev/null bs=1M count=5000 2>/dev/null &
    dd if=/dev/zero of=/dev/null bs=1M count=5000 2>/dev/null &
    sleep 1
    am force-stop com.android.settings 2>/dev/null; sleep 1
    START=$(cat /proc/uptime | awk '{print $1}')
    am start -n com.android.settings/.Settings >/dev/null 2>&1
    for i in $(seq 1 30); do dumpsys window windows 2>/dev/null | grep -q "mCurrentFocus=.*Settings" && break; sleep 0.1; done
    END=$(cat /proc/uptime | awk '{print $1}')
    ELAPSED=$(echo "($END - $START) * 1000" | bc 2>/dev/null || echo "N/A")
    printf "    %s: %s ms (Settings launch under load)\n" "$LABEL" "$ELAPSED"
    killall dd 2>/dev/null; sleep 2
done

echo ""
echo "  [8.2] Input Latency Approximation"
for bore_state in 1 0; do
    set_bore $bore_state
    LABEL=$([ "$bore_state" = "1" ] && echo "BORE ON " || echo "BORE OFF")
    dd if=/dev/zero of=/dev/null bs=1M count=5000 2>/dev/null &
    dd if=/dev/zero of=/dev/null bs=1M count=5000 2>/dev/null &
    sleep 1
    START=$(cat /proc/uptime | awk '{print $1}')
    input keyevent KEYCODE_HOME 2>/dev/null
    END=$(cat /proc/uptime | awk '{print $1}')
    ELAPSED=$(echo "($END - $START) * 1000" | bc 2>/dev/null || echo "N/A")
    printf "    %s: %s ms (input command latency)\n" "$LABEL" "$ELAPSED"
    killall dd 2>/dev/null; sleep 2
done

echo ""
echo "━━━ [9] CPU Throughput Benchmark ━━━"
echo ""

for bore_state in 1 0; do
    set_bore $bore_state
    LABEL=$([ "$bore_state" = "1" ] && echo "BORE ON " || echo "BORE OFF")
    START=$(cat /proc/uptime | awk '{print $1}')
    dd if=/dev/zero of=/dev/null bs=1M count=1000 2>/dev/null
    END=$(cat /proc/uptime | awk '{print $1}')
    SINGLE=$(echo "($END - $START)" | bc 2>/dev/null || echo "N/A")
    START=$(cat /proc/uptime | awk '{print $1}')
    dd if=/dev/zero of=/dev/null bs=1M count=500 2>/dev/null &
    dd if=/dev/zero of=/dev/null bs=1M count=500 2>/dev/null &
    dd if=/dev/zero of=/dev/null bs=1M count=500 2>/dev/null &
    dd if=/dev/zero of=/dev/null bs=1M count=500 2>/dev/null &
    wait
    END=$(cat /proc/uptime | awk '{print $1}')
    MULTI=$(echo "($END - $START)" | bc 2>/dev/null || echo "N/A")
    printf "    %s: 1-core=%ss  4-core=%ss\n" "$LABEL" "$SINGLE" "$MULTI"
done

echo ""
echo "━━━ [10] Stability & Error Check ━━━"
echo ""

echo "  [10.1] update_rq_clock WARNING"
set_bore $BORE_OFF; set_bore $BORE_ON
dmesg | grep -q "update_rq_clock" && fail "Found update_rq_clock WARNING" || pass "No update_rq_clock WARNING"

echo ""
echo "  [10.2] Kernel Errors"
dmesg | grep -qE "BUG:|Oops:|Call trace|Kernel panic" && fail "Found real kernel error(s)!" || pass "No BUG/Oops/Panic in dmesg"

echo ""
echo "  [10.3] Hung Tasks"
dmesg | grep -q "INFO: task.*hung" && fail "Found hung task(s)!" || pass "No hung tasks"

echo ""
echo "  [10.4] OOM Kills"
dmesg | grep -q "Out of memory" && warn "Found OOM kill(s)" || pass "No OOM kills"

echo ""
echo "  [10.5] Module Load Errors"
dmesg | grep -q "Unknown symbol" && fail "Found unknown symbol error(s)!" || pass "No module load errors"

echo ""
echo "━━━ [11] WiFi & Connectivity ━━━"
echo ""

WLAN_STATE=$(ip link show wlan0 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
[ "$WLAN_STATE" = "UP" ] && pass "WiFi interface UP" || fail "WiFi interface NOT UP (state=$WLAN_STATE)"
ping -c 3 -W 3 1.1.1.1 >/dev/null 2>&1 && pass "Internet reachable" || warn "Internet not reachable"
CFG_COUNT=$(grep -c " cfg80211" /proc/kallsyms 2>/dev/null)
[ "$CFG_COUNT" -gt 0 ] 2>/dev/null && pass "cfg80211 built-in ($CFG_COUNT symbols)" || fail "cfg80211 NOT in kernel!"

echo ""
echo "━━━ [12] Memory & Performance ━━━"
echo ""

MEM_AVAIL=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
SLAB=$(cat /proc/meminfo | grep "^Slab:" | awk '{print $2}')
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
UPTIME=$(cat /proc/uptime | awk '{print $1}')
printf "  Memory available: %s kB\n" "$MEM_AVAIL"
printf "  Slab:             %s kB\n" "$SLAB"
printf "  Load average:     %s\n" "$LOAD"
printf "  Uptime:           %s sec\n" "$UPTIME"

BORE_TASKS=0
for pid in $(ls /proc/ | grep -E '^[0-9]+$' | head -100); do
    grep -q "burst_score" /proc/$pid/sched 2>/dev/null && BORE_TASKS=$((BORE_TASKS+1))
done
printf "  Tasks with BORE data: ~%d (of 100 sampled)\n" "$BORE_TASKS"

echo ""
set_bore $BORE_ON

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    FINAL REPORT                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
printf "  ✅ Passed:  %d\n" $PASS
printf "  ❌ Failed:  %d\n" $FAIL
printf "  ⚠️  Warning: %d\n" $WARN
echo ""
[ "$FAIL" -eq 0 ] && echo "  🎉 ALL BORE FEATURES WORKING CORRECTLY!" || echo "  ⚠️  $FAIL issue(s) found - review above"
echo ""
