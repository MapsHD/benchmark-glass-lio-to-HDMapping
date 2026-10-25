#!/usr/bin/env python3
"""Preflight check for the glass-lio benchmark run.

glass-lio subscribes to the LiDAR and IMU topics named in its parameter file
(lidar_topic, imu_topic). The LiDAR topic must be a sensor_msgs/PointCloud2 in
the livox_ros_driver2 PointCloud2 layout, with a float64 per-point `timestamp`
in absolute nanoseconds.

- LiDAR topic in the bag: glass-lio reads it directly.
- Otherwise, a /livox/pointcloud PointCloud2 in the bag (the ROS 1
  livox_ros_driver layout with a float32 per-point `time` offset, e.g. the
  Bunker DVI dataset): livox_format_bridge converts it into the LiDAR topic.
  "<bridge input topic> <bridge output topic>" is written to <bridge_flag_file>.
- Neither, or no IMU topic: glass-lio would process nothing and the run would
  record no output, so the run is stopped (exit code 42, the run script then
  skips the conversion).

Usage: glass_lio_preflight.py <parameter_file.yaml> <ros2_bag_dir> <bridge_flag_file>
"""

import os
import sys

import yaml

POINTCLOUD2 = "sensor_msgs/msg/PointCloud2"
IMU = "sensor_msgs/msg/Imu"
BRIDGE_INPUT = "/livox/pointcloud"


def ros_parameters(config):
    """glass-lio parameter files keep everything under <node or /**>: ros__parameters:."""
    for value in config.values():
        if isinstance(value, dict) and "ros__parameters" in value:
            return value["ros__parameters"]
    raise KeyError("ros__parameters")


def main():
    config_path, bag_dir, flag_file = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        with open(config_path) as f:
            params = ros_parameters(yaml.safe_load(f))
        lidar_topic, imu_topic = params["lidar_topic"], params["imu_topic"]
    except (OSError, KeyError, TypeError, AttributeError, yaml.YAMLError) as e:
        print(f"[preflight] ERROR: cannot read lidar_topic/imu_topic from parameter file {config_path}: {e}")
        sys.exit(42)
    print(f"[preflight] parameter file: {config_path}")
    print(f"[preflight] LiDAR topic: {lidar_topic}  IMU topic: {imu_topic}")

    try:
        with open(os.path.join(bag_dir, "metadata.yaml")) as f:
            info = yaml.safe_load(f)["rosbag2_bagfile_information"]
        topics = {t["topic_metadata"]["name"]: (t["topic_metadata"]["type"], t["message_count"])
                  for t in info["topics_with_message_count"]}
    except (OSError, KeyError, TypeError, yaml.YAMLError) as e:
        print(f"[preflight] ERROR: cannot read the ROS 2 bag metadata in {bag_dir}: {e}")
        sys.exit(42)

    def has(name, msg_type):
        return name in topics and topics[name][0] == msg_type

    ok = True
    if has(lidar_topic, POINTCLOUD2):
        print(f"[preflight] {lidar_topic}: {topics[lidar_topic][1]} msgs, read directly by glass-lio")
    elif has(BRIDGE_INPUT, POINTCLOUD2):
        print(f"[preflight] {lidar_topic} not in the bag; {BRIDGE_INPUT} ({topics[BRIDGE_INPUT][1]} msgs) "
              f"is converted into it by livox_format_bridge")
        with open(flag_file, "w") as f:
            f.write(f"{BRIDGE_INPUT} {lidar_topic}\n")
    else:
        print(f"[preflight] ERROR: neither {lidar_topic} nor {BRIDGE_INPUT} is a {POINTCLOUD2} in the bag.")
        ok = False
    if has(imu_topic, IMU):
        print(f"[preflight] {imu_topic}: {topics[imu_topic][1]} msgs")
    else:
        print(f"[preflight] ERROR: {imu_topic} must be {IMU} ({topics.get(imu_topic, ('not in the bag',))[0]}).")
        ok = False

    if not ok:
        for msg_type in (POINTCLOUD2, IMU):
            names = [t for t, (ty, _) in topics.items() if ty == msg_type]
            print(f"[preflight] {msg_type} topics in this bag: {', '.join(names) or '(none)'}")
        print("[preflight] Set lidar_topic and imu_topic in the parameter file (CONFIG_FILE).")
        sys.exit(42)


if __name__ == "__main__":
    main()
