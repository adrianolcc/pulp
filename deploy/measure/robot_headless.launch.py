"""Headless MoveIt demo for the WP-02 memory measurement.

The same nodes as moveit_resources_panda_moveit_config's demo.launch.py
(move_group, robot_state_publisher, ros2_control with mock hardware and the
arm, hand and joint-state controllers), without RViz: PULP never runs RViz,
the control room draws the robot. The Panda stands in until the real cell is
modelled in WP-13.
"""

from launch import LaunchDescription
from launch_ros.actions import Node
from moveit_configs_utils import MoveItConfigsBuilder

PKG = "moveit_resources_panda_moveit_config"


def generate_launch_description() -> LaunchDescription:
    config = (
        MoveItConfigsBuilder("moveit_resources_panda", package_name=PKG)
        .robot_description(
            file_path="config/panda.urdf.xacro",
            mappings={"ros2_control_hardware_type": "mock_components"},
        )
        .robot_description_semantic(file_path="config/panda.srdf")
        .planning_scene_monitor(
            publish_robot_description=True, publish_robot_description_semantic=True
        )
        .trajectory_execution(file_path="config/gripper_moveit_controllers.yaml")
        .planning_pipelines(pipelines=["ompl", "pilz_industrial_motion_planner"])
        .to_moveit_configs()
    )
    controllers = f"{config.package_path}/config/ros2_controllers.yaml"

    def spawner(name: str) -> Node:
        return Node(
            package="controller_manager",
            executable="spawner",
            arguments=[name, "-c", "/controller_manager", "--param-file", controllers],
        )

    return LaunchDescription(
        [
            Node(
                package="tf2_ros",
                executable="static_transform_publisher",
                arguments=["--frame-id", "world", "--child-frame-id", "panda_link0"],
            ),
            Node(
                package="robot_state_publisher",
                executable="robot_state_publisher",
                parameters=[config.robot_description],
            ),
            Node(
                package="moveit_ros_move_group",
                executable="move_group",
                output="screen",
                parameters=[config.to_dict()],
            ),
            Node(
                package="controller_manager",
                executable="ros2_control_node",
                parameters=[controllers],
                remappings=[("/controller_manager/robot_description", "/robot_description")],
                output="screen",
            ),
            spawner("joint_state_broadcaster"),
            spawner("panda_arm_controller"),
            spawner("panda_hand_controller"),
        ]
    )
