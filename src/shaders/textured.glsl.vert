#version 120

attribute vec2 in_position;
attribute vec2 in_uv;

varying vec2 var_uv;

void main() {
	var_uv = in_uv;
	gl_Position = vec4(in_position, 0.0, 1.0);
}
