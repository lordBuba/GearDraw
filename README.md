# GearDraw

A lightweight GUI for [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp).

GearDraw provides a simple desktop interface for local image generation without requiring a web service.

## Features

* Text-to-image generation
* Image-to-image generation
* Inpainting
* Selectable inpaint regions
* Adjustable mask brush and blur
* Prompt presets
* Generation history
* LoRA model directory support
* Configurable width, height, steps, CFG and seed
* Local image output
* Windows desktop application

## Requirements

* Windows 10/11
* `stable-diffusion.cpp`
* A compatible Stable Diffusion model

## Installation

GearDraw requires `sd-cli.exe` from [stable-diffusion.cpp].

Download and install `stable-diffusion.cpp`, then place the GearDraw files in the **same folder as `sd-cli.exe`**.

The folder should look like this:

```text
stable-diffusion.cpp/
├── GearDraw.exe
├── GearDraw.pck
├── sd-cli.exe
├── models/
└── ...
```

Then simply run `GearDraw.exe`.

GearDraw uses the existing `sd-cli.exe` from your stable-diffusion.cpp installation, so no additional backend installation is required.

[Download stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp/releases)


## Backend

GearDraw uses `stable-diffusion.cpp` as its image generation backend.

## Status

GearDraw is currently in early development.

The core text-to-image, image-to-image and inpainting workflows are functional.

## License

The GearDraw source code is provided under the license included in this repository.

GearDraw uses third-party software and libraries with their own licenses.
