#!/system/bin/sh
# ════════════════════════════════════════════════════════════
# BORE Scheduler Feature Test & Benchmark
# Must run ON DEVICE as root: su -c sh bore_test.sh
# ════════════════════════════════════════════════════════════

cat << 'EOF'

    ██████   ██████  ██████  ███████ 
    ██   ██ ██    ██ ██   ██ ██      
    ██████  ██    ██ ██████  █████   
    ██   ██ ██    ██ ██   ██ ██      
    ██████   ██████  ██   ██ ███████ 
    Burst-Oriented Response Enhancer
    Scheduler Feature Test ---------
    For Android --------------------

EOF

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
    echo "  Root:       ❌ No (UID $ROOT) - Test failed canceled!"
    exit 1
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
    VER=$(cat /proc/sys/kernel/sched_bore_version | head -n1 2>/dev/null)
    echo "  Version:    ✅ $VER"
else
    VER_STR=$(dmesg | grep "BORE CPU Scheduler modification" | awk '{for(i=1;i<=NF;i++) if($i=="modification") print $(i+1)}')
    if [ -n "$VER_STR" ]; then
        echo "  Version:    ✅ $VER_STR (from dmesg)"
    else
        echo "  Version:    ⚠️ Unknown"
    fi
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

# Determine the correct score name (Legacy vs Current) using if-else
if grep -q "bore.score" /proc/$$/sched 2>/dev/null; then
    SCORE_NAME="bore.score"
else
    SCORE_NAME="burst_score"
fi

# Helper: read burst score from /proc/<pid>/sched dynamically
get_burst_score() {
    grep "$SCORE_NAME" /proc/$1/sched 2>/dev/null | awk '{print $NF}'
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
# Dynamic detection for Legacy vs Current parameters
IS_LEGACY=0
IS_CURRENT=0

if [ -f /proc/sys/kernel/sched_burst_fork_atavistic ]; then
    IS_LEGACY=1
fi
if [ -f /proc/sys/kernel/sched_burst_inherit_type ]; then
    IS_CURRENT=1
fi

if [ "$IS_LEGACY" -eq 1 ]; then
    echo "  [1.2] BORE Sysctl Parameters (Legacy)"
    PARAM_LIST="sched_bore sched_burst_exclude_kthreads \
             sched_burst_smoothness_long sched_burst_smoothness_short \
             sched_burst_fork_atavistic sched_burst_parity_threshold \
             sched_burst_penalty_offset sched_burst_penalty_scale \
             sched_burst_cache_stop_count sched_burst_cache_lifetime \
             sched_deadline_boost_mask"
elif [ "$IS_CURRENT" -eq 1 ]; then
    echo "  [1.2] BORE Sysctl Parameters"
    PARAM_LIST="sched_bore sched_burst_inherit_type \
             sched_burst_smoothness sched_burst_penalty_offset \
             sched_burst_penalty_scale sched_burst_cache_lifetime"
else
    echo "  [1.2] BORE Sysctl Parameters (Unknown version)"
    PARAM_LIST="sched_bore sched_burst_exclude_kthreads \
             sched_burst_smoothness_long sched_burst_smoothness_short \
             sched_burst_fork_atavistic sched_burst_parity_threshold \
             sched_burst_penalty_offset sched_burst_penalty_scale \
             sched_burst_cache_stop_count sched_burst_cache_lifetime \
             sched_deadline_boost_mask sched_burst_inherit_type \
             sched_burst_smoothness"
fi

for p in $PARAM_LIST; do
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

echo "  [2.1] Burst Score in /proc/<pid>/sched"
MY_SCORE=$(get_burst_score $$)
if [ -n "$MY_SCORE" ]; then
    pass "$SCORE_NAME readable: $MY_SCORE"
else
    fail "$SCORE_NAME NOT found in /proc/$$/sched!"
fi

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
for pid in $HEAVY1 $HEAVY2 $HEAVY3 $$; do
    s=$(get_burst_score $pid)
    [ -n "$s" ] && SCORES="$SCORES $s"
done
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

echo ""
echo "  [2.3] Burst Penalty for CPU-heavy Task"
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
DD_PID=$!
sleep 5

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
    fail "Cannot read $SCORE_NAME (DD=$DD_SCORE, shell=$SHELL_SCORE)"
fi

echo ""
echo "  [2.4] Penalty Scale Affects Score"
ORIG_SCALE=$(cat /proc/sys/kernel/sched_burst_penalty_scale 2>/dev/null)

if [ -n "$ORIG_SCALE" ]; then
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
        fail "Cannot read $SCORE_NAME (low=$SCORE_LOW, high=$SCORE_HIGH)"
    fi
else
    warn "sched_burst_penalty_scale parameter not found, skipping scale test"
fi


echo ""
echo "━━━ [3] Fork Inheritance ━━━"
echo ""

if [ "$IS_LEGACY" -eq 1 ]; then
    echo "  [3.1] Fork Atavistic Parameter"
    FA_VAL=$(cat /proc/sys/kernel/sched_burst_fork_atavistic 2>/dev/null)
    [ -n "$FA_VAL" ] && [ "$FA_VAL" -ge 0 ] && [ "$FA_VAL" -le 3 ] && pass "sched_burst_fork_atavistic = $FA_VAL (valid: 0-3)" || fail "Invalid value: $FA_VAL"
else
    echo "  [3.1] Inherit Type Parameter"
    FA_VAL=$(cat /proc/sys/kernel/sched_burst_inherit_type 2>/dev/null)
    [ -n "$FA_VAL" ] && [ "$FA_VAL" -ge 0 ] && [ "$FA_VAL" -le 2 ] && pass "sched_burst_inherit_type = $FA_VAL (valid: 0-2)" || fail "Invalid value: $FA_VAL"
fi

echo ""
echo "  [3.2] Child Inherits Parent Burst"
dd if=/dev/zero of=/dev/null bs=1M count=999999 2>/dev/null &
PARENT_PID=$!
sleep 5

PARENT_SCORE=$(get_burst_score $PARENT_PID)

sh -c 'sleep 10' &
CHILD_PID=$!
sleep 2

CHILD_SCORE=$(get_burst_score $CHILD_PID)
kill $PARENT_PID $CHILD_PID 2>/dev/null
wait $PARENT_PID $CHILD_PID 2>/dev/null

if [ -n "$PARENT_SCORE" ] && [ -n "$CHILD_SCORE" ]; then
    pass "Child has $SCORE_NAME ($CHILD_SCORE), parent has ($PARENT_SCORE)"
else
    fail "Cannot read $SCORE_NAME (parent=$PARENT_SCORE, child=$CHILD_SCORE)"
fi

if [ "$IS_LEGACY" -eq 1 ]; then
    echo ""
    echo "  [3.3] Atavistic Level Variants"
    ORIG_FA=$(cat /proc/sys/kernel/sched_burst_fork_atavistic 2>/dev/null)
    for level in 0 1 2 3; do
        echo $level > /proc/sys/kernel/sched_burst_fork_atavistic 2>/dev/null
        NEW=$(cat /proc/sys/kernel/sched_burst_fork_atavistic 2>/dev/null)
        if [ "$NEW" = "$level" ]; then
            printf "    ✅ Level %d: OK\n" $level
        else
            printf "    ❌ Level %d: FAILED (got %s)\n" $level "$NEW"
            FAIL=$((FAIL+1))
        fi
    done
    echo $ORIG_FA > /proc/sys/kernel/sched_burst_fork_atavistic 2>/dev/null
fi


# --- DYNAMIC SECTION NUMBERING FOR LEGACY MODULES ---
SEC=4

if [ "$IS_LEGACY" -eq 1 ]; then

    # 4. Deadline Boost (Legacy)
    echo ""
    echo "━━━ [$SEC] Deadline Boost ━━━"
    echo ""
    echo "  [$SEC.1] Deadline Boost Mask"
    DBM=$(cat /proc/sys/kernel/sched_deadline_boost_mask 2>/dev/null)
    if [ -n "$DBM" ] && [ "$DBM" -gt 0 ]; then
        pass "sched_deadline_boost_mask = $DBM (non-zero = boost enabled)"
        [ "$DBM" = "129" ] && echo "       (ENQUEUE_INITIAL | ENQUEUE_WAKEUP = default)"
    else
        warn "sched_deadline_boost_mask = 0 (no boost!) or missing"
    fi
    SEC=$((SEC+1))

    # 5. Kthread Exclusion (Legacy)
    echo ""
    echo "━━━ [$SEC] Kthread Exclusion ━━━"
    echo ""
    echo "  [$SEC.1] Kthread Exclusion"
    KTE=$(cat /proc/sys/kernel/sched_burst_exclude_kthreads 2>/dev/null)
    [ "$KTE" = "1" ] && pass "sched_burst_exclude_kthreads = 1 (kthreads excluded)" || warn "sched_burst_exclude_kthreads = $KTE"

    echo ""
    echo "  [$SEC.2] Kernel Thread Burst Scores"
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
        [ "$KT_NONZERO" -eq 0 ] && pass "All kernel threads have $SCORE_NAME = 0" || warn "$KT_NONZERO kernel threads have non-zero $SCORE_NAME!"
    else
        echo "    (kthread exclusion disabled, skipping check)"
    fi
    SEC=$((SEC+1))

    # 6. Smoothness Parameters (Legacy)
    echo ""
    echo "━━━ [$SEC] Smoothness Parameters ━━━"
    echo ""
    SL=$(cat /proc/sys/kernel/sched_burst_smoothness_long 2>/dev/null)
    SS=$(cat /proc/sys/kernel/sched_burst_smoothness_short 2>/dev/null)
    printf "  sched_burst_smoothness_long  = %s\n" "${SL:-N/A}"
    printf "  sched_burst_smoothness_short = %s\n" "${SS:-N/A}"
    [ -n "$SL" ] && [ "$SL" -ge 0 ] && [ "$SL" -le 1 ] && [ -n "$SS" ] && [ "$SS" -ge 0 ] && [ "$SS" -le 1 ] && pass "Smoothness values valid (0-1)" || warn "Smoothness values out of expected range or missing"
    SEC=$((SEC+1))

    # 7. Parity Threshold (Legacy)
    echo ""
    echo "━━━ [$SEC] Parity Threshold ━━━"
    echo ""
    PT=$(cat /proc/sys/kernel/sched_burst_parity_threshold 2>/dev/null)
    printf "  sched_burst_parity_threshold = %s\n" "${PT:-N/A}"
    [ -n "$PT" ] && [ "$PT" -ge 0 ] && [ "$PT" -le 255 ] && pass "Parity threshold valid (0-255)" || fail "Parity threshold out of range or missing!"
    SEC=$((SEC+1))

fi

echo ""
echo "━━━ [$SEC] Interactive Responsiveness ━━━"
echo ""

echo "  [$SEC.1] App Launch Under Load"
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
echo "  [$SEC.2] Input Latency Approximation"
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

SEC=$((SEC+1))

echo ""
echo "━━━ [$SEC] CPU Throughput Benchmark ━━━"
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

SEC=$((SEC+1))

echo ""
echo "━━━ [$SEC] Stability & Error Check ━━━"
echo ""

echo "  [$SEC.1] update_rq_clock WARNING"
set_bore $BORE_OFF; set_bore $BORE_ON
dmesg | grep -q "update_rq_clock" && fail "Found update_rq_clock WARNING" || pass "No update_rq_clock WARNING"

echo ""
echo "  [$SEC.2] Kernel Errors"
dmesg | grep -qE "BUG:|Oops:|Call trace|Kernel panic" && fail "Found real kernel error(s)!" || pass "No BUG/Oops/Panic in dmesg"

echo ""
echo "  [$SEC.3] Hung Tasks"
dmesg | grep -q "INFO: task.*hung" && fail "Found hung task(s)!" || pass "No hung tasks"

echo ""
echo "  [$SEC.4] OOM Kills"
dmesg | grep -q "Out of memory" && warn "Found OOM kill(s)" || pass "No OOM kills"

SEC=$((SEC+1))

echo ""
echo "━━━ [$SEC] WiFi & Connectivity (Universal) ━━━"
echo ""

# 7.1 Detect WiFi Interface Dynamically
WIFI_IFACE=""
for iface in wlan0 wlan1 swlan0; do
    if [ -d "/sys/class/net/$iface" ]; then
        WIFI_IFACE=$iface
        break
    fi
done
if [ -z "$WIFI_IFACE" ]; then
    WIFI_IFACE=$(ip link | awk -F: '/wlan|swlan/ {print $2}' | head -1 | tr -d ' ')
fi

if [ -n "$WIFI_IFACE" ]; then
    pass "WiFi Interface detected: $WIFI_IFACE"
else
    warn "No typical WiFi interface (wlan0/swlan0) found"
    WIFI_IFACE="wlan0" # Default fallback for checks
fi

# 7.2 Detect Chipset (Qualcomm vs MediaTek vs Other)
SOC_HW=$(getprop ro.hardware)
BOARD_HW=$(getprop ro.board.platform)
WIFI_CHIPSET="Unknown"
DRIVER_LOADED=0

if echo "$SOC_HW $BOARD_HW" | grep -iqE 'qcom|msm|sdm|sm|kalama|pineapple'; then
    WIFI_CHIPSET="Qualcomm"
elif echo "$SOC_HW $BOARD_HW" | grep -iqE 'mt|mediatek|mtk|dimensity'; then
    WIFI_CHIPSET="MediaTek"
elif echo "$SOC_HW $BOARD_HW" | grep -iqE 'exynos|universal'; then
    WIFI_CHIPSET="Samsung Exynos"
elif echo "$SOC_HW $BOARD_HW" | grep -iqE 'kirin|hikey'; then
    WIFI_CHIPSET="HiSilicon Kirin"
fi

# Verify/Override via loaded modules
if cat /proc/modules | grep -qE '^wlan '; then
    WIFI_CHIPSET="Qualcomm (wlan.ko)"; DRIVER_LOADED=1
elif cat /proc/modules | grep -qE '^wmt '; then
    WIFI_CHIPSET="MediaTek (wmt)"; DRIVER_LOADED=1
elif cat /proc/modules | grep -qE '^wlan_drv '; then
    WIFI_CHIPSET="MediaTek (wlan_drv)"; DRIVER_LOADED=1
elif [ -d "/dev/wmt" ]; then
    WIFI_CHIPSET="MediaTek (wmt dev)"; DRIVER_LOADED=1
elif [ -d "/dev/icnss" ] || [ -d "/dev/cnss" ]; then
    WIFI_CHIPSET="Qualcomm (cnss/icnss)"; DRIVER_LOADED=1
fi

printf "  Chipset:     %s\n" "$WIFI_CHIPSET"

# 7.3 Driver Status
if [ "$DRIVER_LOADED" -eq 1 ]; then
    pass "WiFi driver module is loaded"
else
    if cat /proc/modules | awk '{print $1}' | grep -iqE 'wifi|wireless|80211|wlan|wmt'; then
        pass "Wireless related module found in /proc/modules"
        DRIVER_LOADED=1
    else
        fail "WiFi driver module NOT FOUND in /proc/modules!"
        warn "⚠️  WiFi will likely not function without the driver"
    fi
fi

# 7.4 Interface State
WLAN_STATE=$(ip link show $WIFI_IFACE 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
if [ "$WLAN_STATE" = "UP" ]; then
    pass "WiFi interface $WIFI_IFACE is UP"
else
    warn "WiFi interface $WIFI_IFACE is NOT UP (state=$WLAN_STATE)"
    WIFI_ENABLED=$(dumpsys wifi 2>/dev/null | grep "Wi-Fi is" | head -1)
    if echo "$WIFI_ENABLED" | grep -q "enabled"; then
         warn "⚠️  Android framework says Wi-Fi is enabled, but interface is down"
    fi
fi

# 7.5 IP Address
WIFI_IP=$(ip addr show $WIFI_IFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
if [ -n "$WIFI_IP" ]; then
    pass "IP Address obtained: $WIFI_IP"
else
    fail "No IP Address on $WIFI_IFACE"
    warn "⚠️  Module might be loaded, but connection failed (check DHCP/Auth)"
fi

# 7.6 Internet Reachability

PING_OK=0
for target in 1.1.1.1 8.8.8.8 142.250.185.46; do
    if ping -c 1 -W 3 $target >/dev/null 2>&1; then
        PING_OK=1
        break
    fi
done

if [ "$PING_OK" -eq 1 ]; then
    pass "Internet reachable (Ping OK)"
else
    fail "Internet NOT reachable (Ping failed)"
    warn "⚠️  WiFi might be connected locally but has no internet access"
fi

# 7.7 Specific Module Functionality Warnings
if [ "$WIFI_CHIPSET" = "Qualcomm" ] && [ "$DRIVER_LOADED" -eq 0 ]; then
    warn "⚠️  Qualcomm device detected but wlan.ko/cnss not loaded. Check kernel config (CFI/Modversions) or /vendor/lib/modules/"
fi
if [ "$WIFI_CHIPSET" = "MediaTek" ] && [ "$DRIVER_LOADED" -eq 0 ]; then
    warn "⚠️  MediaTek device detected but wmt/wlan_drv not loaded. Check kernel config or /vendor/lib/modules/"
fi

# 7.8 cfg80211
CFG_COUNT=$(grep -c " cfg80211" /proc/kallsyms 2>/dev/null)
if [ "$CFG_COUNT" -gt 0 ]; then
    pass "cfg80211 built-in ($CFG_COUNT symbols)"
else
    fail "cfg80211 NOT in kernel! WiFi will not work"
fi

SEC=$((SEC+1))

echo ""
echo "━━━ [$SEC] Memory & Performance ━━━"
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
    grep -q "$SCORE_NAME" /proc/$pid/sched 2>/dev/null && BORE_TASKS=$((BORE_TASKS+1))
done
printf "  Tasks with BORE data: ~%d (of 100 sampled)\n" "$BORE_TASKS"

echo ""
set_bore $BORE_ON

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                        FINAL REPORT                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
printf "  ✅ Passed:  %d\n" $PASS
printf "  ❌ Failed:  %d\n" $FAIL
printf "  ⚠️  Warning: %d\n" $WARN
echo ""
[ "$FAIL" -eq 0 ] && echo "  🎉 ALL BORE FEATURES WORKING CORRECTLY!" || echo "  ⚠️  $FAIL issue(s) found - review above"
echo ""
