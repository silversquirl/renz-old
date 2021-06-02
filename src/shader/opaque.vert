#version 450 core

layout(location = 0) in vec3 i_pos;
layout(location = 1) in vec3 i_norm;
layout(location = 2) in vec4 i_color;
uniform mat4 u_transform;
out vec4 v_color;

void main() {
	gl_Position = vec4(i_pos, 1) * u_transform;
	v_color = i_color;
}
