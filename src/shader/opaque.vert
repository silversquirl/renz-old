#version 450 core

layout(location = 0) in vec3 i_pos;
layout(location = 1) in vec3 i_norm;
uniform mat4 u_transform;

void main() {
	gl_Position = vec4(i_pos, 1) * u_transform;
}
