#!/bin/bash
# Run glass-lio on a rosbag (ROS 2 bag directory or ROS 1 .bag), record output
# topics, then convert the recorded bag to an HDMapping session.
#
# glass-lio publishes the sensor pose on /glasslio_node/odom and the deskewed
# scan in the sensor frame on /glasslio_node/deskewed (only while someone
# subscribes, which the recorder does), both stamped with the input scan's
# header stamp, i.e. bag time. glass-lio's clock is left untouched (no
# use_sim_time, as in its own run scripts); the converter transforms every scan
# into the world frame with the pose of the same stamp.
#
# glass-lio reads the livox_ros_driver2 PointCloud2 layout (float64 per-point
# `timestamp`, absolute nanoseconds). A bag that only has /livox/pointcloud in
# the ROS 1 livox_ros_driver layout (float32 per-point `time` offset, e.g. the
# Bunker DVI dataset) is converted on the fly by livox_format_bridge into
# glass-lio's LiDAR topic; the preflight check decides this from the bag.

IMAGE_NAME='glass-lio_humble'
TMUX_SESSION='ros2_glass_lio'

DATASET_CONTAINER_PATH='/ros2_ws/dataset/input.bag'
DATASET_ROS2_PATH='/tmp/dataset_ros2'
BAG_OUTPUT_CONTAINER='/ros2_ws/recordings'
CONFIG_MOUNT_CONTAINER='/ros2_ws/config/glass_lio.yaml'
CONFIG_DIR_CONTAINER='/ros2_ws/install/glasslio/share/glasslio/config'
BRIDGE_FLAG_CONTAINER='/tmp/glass_lio_bridge_input'

RECORDED_BAG_NAME="recorded-glass-lio"
HDMAPPING_OUT_NAME="output_hdmapping"

# Recorded topics (used by the converter).
ODOM_TOPIC="${ODOM_TOPIC:-/glasslio_node/odom}"
CLOUD_TOPIC="${CLOUD_TOPIC:-/glasslio_node/deskewed}"

# glass-lio parameter file (topics, extrinsic, IMU units, voxel sizes): a file
# on the host, or the name of one shipped with glass-lio in its config/ folder.
# Default: glass-lio's own livox_mid_360.yaml.
CONFIG_FILE="${CONFIG_FILE:-livox_mid_360.yaml}"

# RViz on by default — the live view of how glass-lio tracks the dataset.
USE_RVIZ="${USE_RVIZ:-1}"

# Force Mesa software rendering by default so RViz renders even when the host
# GPU driver is not exposed to the container (the libGL "nvidia-drm" / amdgpu case).
LIBGL_SW="${LIBGL_SW:-1}"
if [[ "$LIBGL_SW" == "1" ]]; then LIBGL_ENV="1"; else LIBGL_ENV=""; fi

usage() {
  echo "Usage:"
  echo "  $0 <ros2_bag_dir | input.bag> <output_dir>"
  echo
  echo "  ros2_bag_dir : ROS 2 bag directory — played directly, no conversion"
  echo "                 (this is what the HDMapping orchestration passes)"
  echo "  input.bag    : ROS 1 bag file — converted to ROS 2 format first"
  echo
  echo "If no arguments are provided, a GUI file selector will be used."
  echo
  echo "Environment variables:"
  echo "  CONFIG_FILE  - glass-lio parameter file: a host *.yaml, or the name of one in"
  echo "                 glass-lio's config/ folder       (default: livox_mid_360.yaml)"
  echo "  ODOM_TOPIC   - glass-lio odometry output topic  (default: /glasslio_node/odom)"
  echo "  CLOUD_TOPIC  - glass-lio deskewed scan topic    (default: /glasslio_node/deskewed)"
  echo "  USE_RVIZ     - 1/0, launch RViz live view       (default: 1)"
  echo "  PLAY_RATE    - ros2 bag play rate               (default: 1.0)"
  exit 1
}

echo "=== glass-lio rosbag pipeline ==="

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

if [[ $# -eq 2 ]]; then
  DATASET_HOST_PATH="$1"
  BAG_OUTPUT_HOST="$2"
elif [[ $# -eq 0 ]]; then
  command -v zenity >/dev/null || {
    echo "Error: zenity is not available"
    exit 1
  }
  DATASET_HOST_PATH=$(zenity --file-selection --title="Select BAG file (or ROS 2 bag directory)")
  BAG_OUTPUT_HOST=$(zenity --file-selection --directory --title="Select output directory")
else
  usage
fi

if [[ -z "$DATASET_HOST_PATH" || -z "$BAG_OUTPUT_HOST" ]]; then
  echo "Error: no file or directory selected"
  exit 1
fi

if [[ ! -e "$DATASET_HOST_PATH" ]]; then
  echo "Error: input does not exist: $DATASET_HOST_PATH"
  exit 1
fi

# Parameter file: a host file is mounted into the container; a plain name is
# a file shipped with glass-lio (checked inside the container).
CONFIG_MOUNT=()
if [[ -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE=$(realpath "$CONFIG_FILE")
  CONFIG_MOUNT=(-v "$CONFIG_FILE":"$CONFIG_MOUNT_CONTAINER":ro)
  CONFIG_CONTAINER="$CONFIG_MOUNT_CONTAINER"
  CONFIG_DESC="$CONFIG_FILE (host)"
elif [[ "$CONFIG_FILE" != */* ]]; then
  CONFIG_CONTAINER="$CONFIG_DIR_CONTAINER/$CONFIG_FILE"
  CONFIG_DESC="$CONFIG_FILE (glass-lio config/)"
else
  echo "Error: CONFIG_FILE does not exist: $CONFIG_FILE"
  exit 1
fi

mkdir -p "$BAG_OUTPUT_HOST"

DATASET_HOST_PATH=$(realpath "$DATASET_HOST_PATH")
BAG_OUTPUT_HOST=$(realpath "$BAG_OUTPUT_HOST")

# Orchestration convention: a directory input is an already-converted ROS 2 bag
# (played directly); a file input is a ROS 1 .bag (converted first).
if [[ -d "$DATASET_HOST_PATH" ]]; then
  INPUT_IS_DIR=1
else
  INPUT_IS_DIR=0
fi

echo "Input           : $DATASET_HOST_PATH ($([[ $INPUT_IS_DIR == 1 ]] && echo 'ROS 2 bag directory' || echo 'ROS 1 bag file, converted to ROS 2'))"
echo "Output dir      : $BAG_OUTPUT_HOST"
echo "Parameter file  : $CONFIG_DESC"
echo "Odom topic      : $ODOM_TOPIC"
echo "Cloud topic     : $CLOUD_TOPIC"

xhost +local:docker >/dev/null

# ── Phase 1: run glass-lio + record output topics ────────────────────────────
docker run -it --rm \
  --network host \
  -e DISPLAY=$DISPLAY \
  -e ROS_HOME=/tmp/.ros \
  -e LIBGL_ALWAYS_SOFTWARE="$LIBGL_ENV" \
  -e USE_RVIZ="$USE_RVIZ" \
  -e CONFIG_CONTAINER="$CONFIG_CONTAINER" \
  -e ODOM_TOPIC="$ODOM_TOPIC" \
  -e CLOUD_TOPIC="$CLOUD_TOPIC" \
  -e INPUT_IS_DIR="$INPUT_IS_DIR" \
  -e PLAY_RATE="${PLAY_RATE:-1.0}" \
  -u 1000:1000 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$DATASET_HOST_PATH":"$DATASET_CONTAINER_PATH":ro \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  "${CONFIG_MOUNT[@]}" \
  "$IMAGE_NAME" \
  /bin/bash -c '

    source /opt/ros/humble/setup.bash
    source /ros2_ws/install/setup.bash

    # ── Convert ROS 1 bag to ROS 2 format if needed ──────────────────────────
    if [[ "$INPUT_IS_DIR" == "1" ]]; then
      echo "[convert] Input is already a ROS 2 bag directory — skipping conversion."
      ROS2_BAG="'"$DATASET_CONTAINER_PATH"'"
    else
      echo "[convert] Converting ROS 1 bag to ROS 2 format..."
      rm -rf "'"$DATASET_ROS2_PATH"'"
      rosbags-convert "'"$DATASET_CONTAINER_PATH"'" --dst "'"$DATASET_ROS2_PATH"'" || {
        echo "[convert] ERROR: rosbags-convert failed"; exit 1; }
      ROS2_BAG="'"$DATASET_ROS2_PATH"'"
    fi

    export ROS2_BAG
    echo "[convert] ROS 2 bag ready at: $ROS2_BAG"
    ls -la $ROS2_BAG/

    # ── Preflight: the LiDAR and IMU topics of the parameter file must be ────
    # playable, otherwise glass-lio processes nothing and the run records no
    # output. Decides whether livox_format_bridge is needed.
    rm -f '"$BRIDGE_FLAG_CONTAINER"'
    if ! python3 /ros2_ws/scripts/glass_lio_preflight.py "$CONFIG_CONTAINER" "$ROS2_BAG" '"$BRIDGE_FLAG_CONTAINER"'; then
      echo "[preflight] input check failed, nothing is run"
      exit 42
    fi
    if [[ -f '"$BRIDGE_FLAG_CONTAINER"' ]]; then
      read -r BRIDGE_INPUT BRIDGE_OUTPUT < '"$BRIDGE_FLAG_CONTAINER"'
    else
      BRIDGE_INPUT=""
      BRIDGE_OUTPUT=""
    fi
    export BRIDGE_INPUT BRIDGE_OUTPUT

    # Diagnostic logs, next to the recording. Exported so the shells of the
    # tmux panes inherit it.
    export LOG_DIR='"$BAG_OUTPUT_CONTAINER"'/logs
    mkdir -p "$LOG_DIR"
    rm -f "$LOG_DIR"/*.log
    echo "[setup] diagnostic logs -> $LOG_DIR"

    tmux new-session -d -s '"$TMUX_SESSION"'

    # ---------- PANE 0: glass-lio ----------
    tmux send-keys -t '"$TMUX_SESSION"' '\''
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
echo "[glass-lio] launching glasslio.launch.py (config=$CONFIG_CONTAINER) ..."
stdbuf -oL -eL ros2 launch glasslio glasslio.launch.py config:=$CONFIG_CONTAINER 2>&1 | tee "$LOG_DIR"/glass_lio.log
'\'' C-m

    # ---------- PANE 1: ros2 bag record ----------
    tmux split-window -v -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 2
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
rm -rf '"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME"'
echo "[record] start"
ros2 bag record $ODOM_TOPIC $CLOUD_TOPIC -o '"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME"'
echo "[record] exit"
'\'' C-m

    # ---------- PANE 2: ros2 bag play ----------
    tmux split-window -v -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 6
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
echo "[play] start"
ros2 bag play $ROS2_BAG --rate ${PLAY_RATE:-1.0}; tmux wait-for -S BAG_DONE;
echo "[play] done"
'\'' C-m

    # ---------- PANE 3: Livox PointCloud2 format bridge (if needed) ----------
    tmux split-window -v -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
if [[ -n "$BRIDGE_INPUT" ]]; then
  echo "[bridge] livox_format_bridge: $BRIDGE_INPUT (float time) -> $BRIDGE_OUTPUT (double timestamp, ns)"
  stdbuf -oL -eL ros2 run glass_lio_to_hdmapping livox_format_bridge --ros-args -p input_topic:=$BRIDGE_INPUT -p output_topic:=$BRIDGE_OUTPUT 2>&1 | tee "$LOG_DIR"/bridge.log
else
  echo "[bridge] not needed: the bag has the LiDAR topic of the parameter file"
fi
'\'' C-m

    # ---------- PANE 4: RViz ----------
    tmux split-window -v -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 2
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
if [[ "$USE_RVIZ" == "1" ]]; then
  echo "[rviz] launching RViz2..."
  rviz2 -d /ros2_ws/install/glasslio/share/glasslio/rviz/glasslio.rviz
else
  echo "[rviz] disabled (USE_RVIZ=0)"
fi
'\'' C-m

    # ---------- PANE 5: diagnostics ----------
    tmux split-window -h -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 12
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
(
echo "=== ROS 2 DIAGNOSTICS ==="
echo ""
echo "--- Active topics ---"
ros2 topic list
echo ""
for t in $BRIDGE_INPUT $BRIDGE_OUTPUT /livox/imu $ODOM_TOPIC $CLOUD_TOPIC; do
  echo "--- hz $t ---"
  timeout 5 ros2 topic hz $t 2>&1 | tail -2
done
) 2>&1 | tee "$LOG_DIR"/diag.log
echo ""
echo "[diag] done — you can type ROS 2 commands here, e.g.:"
echo "  ros2 topic echo $ODOM_TOPIC --once"
'\'' C-m

    # ---------- Control window (window 1) ----------
    # This is the window the user attaches to; the noisy panes are on window 0.
    # It waits for the play pane to signal end of playback, then tears the whole
    # session down.
    tmux new-window -t '"$TMUX_SESSION"' -n control '\''
source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash
echo "[control] waiting for bag playback to finish..."
echo "(logs -> $LOG_DIR/{glass_lio,bridge,diag}.log)"
tmux wait-for BAG_DONE
echo "[control] bag playback finished — shutting down"

# Give glass-lio a moment to process remaining queued scans
sleep 3

echo ""
echo "--- glass_lio.log: last 5 WARN / ERROR lines ---"
grep -E "\[WARN\]|\[ERROR\]" "$LOG_DIR"/glass_lio.log 2>/dev/null | tail -5
echo "--- glass_lio.log: last 3 lines ---"
tail -3 "$LOG_DIR"/glass_lio.log 2>/dev/null
echo ""

# Graceful stop: Ctrl+C to each pane, the recorder first so its bag is closed cleanly
# Pane layout: 0=glass-lio, 1=recorder, 2=play, 3=bridge, 4=rviz, 5=diag
echo "[control] sending Ctrl+C to all panes..."
tmux send-keys -t '"$TMUX_SESSION"':0.1 C-c
sleep 3
tmux send-keys -t '"$TMUX_SESSION"':0.0 C-c
tmux send-keys -t '"$TMUX_SESSION"':0.3 C-c
tmux send-keys -t '"$TMUX_SESSION"':0.4 C-c
sleep 3

# Force-kill by process name
echo "[control] force-killing remaining processes..."
pkill -9 glasslio_node    2>/dev/null || true
pkill -9 livox_format     2>/dev/null || true
pkill -9 rviz2            2>/dev/null || true
sleep 1

echo "[control] terminating tmux"
tmux kill-server
'\''

    tmux attach -t '"$TMUX_SESSION"'
  '

# The preflight check failed: nothing was recorded, and converting would pick
# up a stale recording from an earlier run.
if [[ $? -eq 42 ]]; then
  echo "=== ABORTED: input check failed, no conversion ==="
  exit 1
fi

# ── Phase 2: convert recorded bag to HDMapping session ────────────────────────
echo "=== Converting recorded bag to HDMapping session ==="

docker run -it --rm \
  --network host \
  -e ROS_HOME=/tmp/.ros \
  -u 1000:1000 \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  "$IMAGE_NAME" \
  /bin/bash -c "
    set -e
    source /opt/ros/humble/setup.bash
    source /ros2_ws/install/setup.bash
    ros2 run glass_lio_to_hdmapping listener \
      \"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME\" \
      \"$BAG_OUTPUT_CONTAINER/$HDMAPPING_OUT_NAME-glass-lio\" \
      \"$ODOM_TOPIC\" \
      \"$CLOUD_TOPIC\"
  "

echo "=== DONE ==="
