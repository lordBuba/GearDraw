# GearDraw

A lightweight GUI for [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp).

GearDraw provides a simple desktop interface for local image generation.

## Features

* Text-to-image generation
* Image-to-image generation
* Inpainting
* **Selectable inpaint regions** for refining small details, faces, hands, or other specific areas of an image

* Adjustable mask brush and blur
* Prompt presets
* Generation history
* LoRA model directory support
* Configurable width, height, steps, CFG and seed
* Local image output
* Windows desktop application

## Requirements

* Windows 10/11
* A **Windows binary release of stable-diffusion.cpp**
* A compatible Stable Diffusion model

GearDraw uses `stable-diffusion.cpp` as its generation backend. It does not include `stable-diffusion.cpp` or `sd-cli.exe`.

### Installation

1. Download a Windows release of [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp), I use [this version.](https://github.com/leejet/stable-diffusion.cpp/releases/download/master-860-44dd137/sd-master-44dd137-bin-win-vulkan-x64.zip).
2. Extract the entire stable-diffusion.cpp archive.
3. Copy `GearDraw.exe` and `GearDraw.pck` into the same folder as `sd-cli.exe`.

4. Start `GearDraw.exe`.

Example:

```text
stable-diffusion.cpp/
├── GearDraw.exe
├── GearDraw.pck
├── sd-cli.exe
├── *.dll
├── ...

```

GearDraw requires the stable-diffusion.cpp runtime and backend files that come with the downloaded binary release. `sd-cli.exe` should not be distributed separately from its accompanying files.



## Backend

GearDraw uses `stable-diffusion.cpp` as its image generation backend.

## Status

GearDraw is currently in early development.

The core text-to-image, image-to-image and inpainting workflows are functional.

## License

The GearDraw source code is provided under the license included in this repository.

GearDraw uses third-party software and libraries with their own licenses.
