## Hint

Please change branch to [Bunker-DVI-Dataset-reg-1](https://github.com/MapsHD/benchmark-glass-lio-to-HDMapping/tree/Bunker-DVI-Dataset-reg-1) for quick experiment.

## Example Dataset:

Download the dataset from [Bunker DVI Dataset](https://charleshamesse.github.io/bunker-dvi-dataset/)

# benchmark-glass-lio-to-HDMapping

Runs the [glass-lio](https://github.com/Tim-HW/glass-lio) LiDAR-inertial
odometry on a ROS 2 (or ROS 1) bag and converts the output to an
[HDMapping](https://github.com/MapsHD/HDMapping) session.

glass-lio is a scan-to-map LiDAR-inertial odometry for Livox sensors: gyro
deskew, a voxel-plane local map, and point-to-plane registration solved by
Gauss-Newton on SE(3), tightly coupled with on-manifold IMU preintegration. Its
estimation engine, glass_core, is a git submodule of glass-lio.

## Prerequisites

- Docker
- A ROS 2 bag directory (or a ROS 1 bag, converted to ROS 2 automatically)
  with a `sensor_msgs/Imu` topic and a `sensor_msgs/PointCloud2` LiDAR topic in
  the livox_ros_driver2 PointCloud2 layout (float64 per-point `timestamp` in
  nanoseconds). A `/livox/pointcloud` in the older livox_ros_driver layout
  (float32 per-point `time` offset) is converted to that layout on the fly.

## Step 1 — Clone with submodules

```bash
git clone https://github.com/MapsHD/benchmark-glass-lio-to-HDMapping.git --recursive
cd benchmark-glass-lio-to-HDMapping
```

## Step 2 — Build the Docker image

```bash
docker build -t glass-lio_humble .
```

This installs:
- Ubuntu 22.04 + ROS 2 Humble
- Eigen3, PCL
- colcon workspace with `glasslio` (including glass_core) and `glass_lio_to_hdmapping`

## Step 3 — Run the pipeline

```bash
chmod +x docker_session_run-ros2-glass-lio.sh
./docker_session_run-ros2-glass-lio.sh /path/to/ros2_bag_dir /path/to/output/dir
```

A ROS 1 `.bag` file works as input too; it is converted to ROS 2 first. Or run
with no arguments to use a GUI file selector (requires `zenity`).

| Variable | Default | Meaning |
|----------|---------|---------|
| `CONFIG_FILE` | `livox_mid_360.yaml` | glass-lio parameter file: topics, LiDAR-IMU extrinsic, IMU units, voxel sizes. A file on the host, or the name of one in glass-lio's [config/](https://github.com/Tim-HW/glass-lio/tree/main/config) folder |
| `USE_RVIZ` | `1` | RViz live view |
| `PLAY_RATE` | `1.0` | ros2 bag play rate (lower it if glass-lio cannot keep up) |

The default `livox_mid_360.yaml` is glass-lio's own configuration for a Livox
Mid-360 with its built-in IMU. For your own sensor, copy it, set
`lidar_topic`, `imu_topic`, `imu.accel_in_g` and the LiDAR-IMU extrinsic, and
pass the file:

```bash
CONFIG_FILE=/path/to/my_sensor.yaml \
  ./docker_session_run-ros2-glass-lio.sh /path/to/ros2_bag_dir /path/to/output/dir
```

Before anything starts, the script checks the bag: the LiDAR topic of the
parameter file is played directly; if it is missing but the bag has a
`/livox/pointcloud` PointCloud2, `livox_format_bridge` converts that into the
LiDAR topic; without either, or without the IMU topic, the run stops.

**What happens:**

The script opens a Docker container with a tmux session containing six panes on
window 0 and a `control` window (window 1, the attach target):

| Pane | Role |
|------|------|
| 0 | `ros2 launch glasslio glasslio.launch.py` — glass-lio |
| 1 | `ros2 bag record /glasslio_node/odom /glasslio_node/deskewed` |
| 2 | `ros2 bag play` — plays your input bag |
| 3 | `livox_format_bridge` — only when the bag needs it |
| 4 | RViz live view |
| 5 | diagnostics — shows active topics and publishing rates |

When playback finishes, the control window stops the recorder, kills all nodes
and RViz, and exits tmux. A second Docker run then converts the recorded bag
into the HDMapping session format. Logs are written to `<output_dir>/logs/`.

## Step 4 — Open in HDMapping

Output files appear in `<output_dir>/output_hdmapping-glass-lio/`:

```
lio_initial_poses.reg
poses.reg
scan_lio_0.laz
...
session.json
trajectory_lio_0.csv
...
```

Open `session.json` with the
[multi_view_tls_registration_step_2](https://github.com/MapsHD/HDMapping)
application.

## Notes on glass-lio

glass-lio publishes:

| Topic | Type | Meaning |
|-------|------|---------|
| `/glasslio_node/odom` | `nav_msgs/Odometry` | the 6-DoF sensor (`livox_frame`) pose in the `odom` frame, one per scan |
| `/glasslio_node/deskewed` | `sensor_msgs/PointCloud2` | the deskewed scan in the sensor frame, one per scan |
| `/glasslio_node/local_map` | `sensor_msgs/PointCloud2` | the local voxel map, for display |

The converter records `/glasslio_node/odom` + `/glasslio_node/deskewed` and
transforms each scan into the world frame with its matching pose. glass-lio
publishes the deskewed scan only while someone subscribes to it, so the
recorder is started before playback.

**Timestamps:** the benchmark does not change glass-lio's clock (no
`use_sim_time`, as in glass-lio's own run scripts). glass-lio stamps its outputs
with the input scan's header stamp, and `livox_format_bridge` keeps that stamp,
so the result is in bag time.

## Contact

januszbedkowski@gmail.com
