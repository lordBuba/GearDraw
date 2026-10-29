# GearDraw

GearDraw is a lightweight Windows GUI for [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp), built with Godot 4.

It provides a simple interface for image generation, image editing, inpainting, and upscaling without requiring a browser-based UI.

## Features

- **Text-to-Image**: Generate images from prompts.
- **Image-to-Image**: Modify existing images using prompts and strength control.
- **Inpainting**: Edit selected areas with a brush, adjustable brush size, and mask blur.
- **Region Inpainting**: Select a specific image region for targeted editing.
- **Upscale**: Increase image resolution using tiled img2img generation and blending.
- **Generation Settings**: Adjust image dimensions, sampling steps, CFG scale, seed, and other parameters.
- **Prompt Presets**: Save, manage, and reuse prompts.
- **Generation History**: Keep track of recent generations.
- **LoRA Support**: Configure a directory containing LoRA models.

## Requirements

- Windows 10 or Windows 11.
- A compatible Stable Diffusion model.

## Installation

1. Download a compatible Windows build of [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp). The current setup uses [this](https://github.com/leejet/stable-diffusion.cpp/releases/tag/master-984-939895f).
2. Extract the backend files into a folder.
3. Place `GearDraw.exe` and `GearDraw.pck` in the same folder as `sd-server.exe` and its required dependencies.
4. Launch `GearDraw.exe`.

Make sure the backend's required DLL files and other dependencies remain in place.

## Backend

GearDraw communicates with `sd-server.exe` through its local HTTP API. The server handles image generation and editing requests, while GearDraw provides the user interface and manages generation settings, masks, and output images.

## Upscaling

The Upscale mode uses img2img generation on image tiles. Overlapping tiles are blended to reduce visible seams and preserve a consistent result across the enlarged image.

## Status

GearDraw is a work in progress. Features and the interface may change as development continues.


