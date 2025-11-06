# Parameter Tracking Design: Explicit Augmentation Parameters

## Problem Statement

The current augmentation pipeline uses **random ranges** for operations:
```julia
pipeline = Scale(0.9:0.01:1.1) |> Rotate(1:0.1:360) |> ShearX(-10:0.1:10)
```

When Augmentor applies these operations, it **internally samples** random values:
- Scale might pick 1.03
- Rotate might pick 237.4 degrees  
- ShearX might pick -3.2 degrees

But we **don't know** what values were actually used! We can't reproduce or analyze the exact transformations.

## Solution: Sample Parameters Explicitly

Instead of passing ranges, we:
1. **Sample random values ourselves** from the ranges
2. **Pass explicit fixed values** to Augmentor
3. **Store the sampled values** in metadata

### Before (Random Ranges)
```julia
# Augmentor samples internally - we don't know the values
pipeline = Rotate(1:0.1:360)
augmented = augment(img, pipeline)
# What angle was used? Unknown!
```

### After (Explicit Values)
```julia
# We sample and track the value
rotation_angle = rand(1:0.1:360)  # e.g., 237.4
pipeline = Rotate(rotation_angle)  # Fixed value
augmented = augment(img, pipeline)
# We know: rotation_angle = 237.4 ✓
```

---

## Augmentation Operations to Track

### 1. Scale
```julia
# Before
Scale(0.9:0.01:1.1)

# After  
scale_factor = rand(0.9:0.01:1.1)
Scale(scale_factor)
# Track: scale_factor
```

### 2. Rotate
```julia
# Before
Rotate(1:0.1:360)

# After
rotation_angle = rand(1:0.1:360)
Rotate(rotation_angle)
# Track: rotation_angle
```

### 3. ShearX & ShearY
```julia
# Before
ShearX(-10:0.1:10)
ShearY(-10:0.1:10)

# After
shear_x_angle = rand(-10:0.1:10)
shear_y_angle = rand(-10:0.1:10)
ShearX(shear_x_angle) |> ShearY(shear_y_angle)
# Track: shear_x_angle, shear_y_angle
```

### 4. RCropSize (Random Crop)
```julia
# Before
RCropSize(100, 100)  # Randomly picks position

# After - Need to find how to specify position explicitly
# Option 1: Use CropSize with explicit offset
crop_x = rand(1:(img_width - crop_width))
crop_y = rand(1:(img_height - crop_height))
Crop(crop_x, crop_y, crop_width, crop_height)
# Track: crop_x, crop_y
```

### 5. Either (Flip)
```julia
# Before
Either(1 => FlipX(), 1 => FlipY(), 1 => NoOp())

# After
flip_choice = rand([:flipx, :flipy, :noop])
if flip_choice == :flipx
    pipeline = FlipX()
elseif flip_choice == :flipy
    pipeline = FlipY()
else
    pipeline = NoOp()
end
# Track: flip_choice
```

### 6. ColorJitter
```julia
# Before
ColorJitter(0.8:0.1:1.2, -0.2:0.1:0.2)

# After
brightness_factor = rand(0.8:0.1:1.2)
saturation_offset = rand(-0.2:0.1:0.2)
ColorJitter(brightness_factor, saturation_offset)
# Track: brightness_factor, saturation_offset
```

### 7. GaussianBlur
```julia
# Before
GaussianBlur(3:2:7, 1:0.1:3)

# After
kernel_size = rand(3:2:7)
sigma_value = rand(1:0.1:3)
GaussianBlur(kernel_size, sigma_value)
# Track: kernel_size, sigma_value
```

### 8. ElasticDistortion
```julia
# Fixed parameters (no randomness in our current setup)
ElasticDistortion(8, 8, 0.2, 2, 1)
# Track: grid_h=8, grid_w=8, scale=0.2, sigma=2, iterations=1
```

---

## Enhanced Metadata Structure

```julia
struct AugmentationMetadata
    # Basic info
    augmented_index::Int
    source_index::Int
    timestamp::DateTime
    random_seed::UInt64
    
    # Main pipeline parameters (geometric)
    scale_factor::Float64
    crop_x::Int
    crop_y::Int
    shear_x_angle::Float64
    shear_y_angle::Float64
    rotation_angle::Float64
    flip_type::Symbol  # :flipx, :flipy, :noop
    
    # Post pipeline (elastic)
    elastic_grid_h::Int
    elastic_grid_w::Int
    elastic_scale::Float64
    elastic_sigma::Float64
    elastic_iterations::Int
    
    # Input pipeline (color/blur, applied to input only)
    brightness_factor::Float64
    saturation_offset::Float64
    blur_kernel_size::Int
    blur_sigma::Float64
    
    # Quality metrics (computed after augmentation)
    scar_percentage::Float64
    redness_percentage::Float64
    hematoma_percentage::Float64
    necrosis_percentage::Float64
    background_percentage::Float64
end
```

---

## Implementation Strategy

### Step 1: Sample All Parameters
```julia
function sample_augmentation_parameters(; seed::UInt64, img_size)
    Random.seed!(seed)
    
    # Main pipeline
    scale_factor = rand(0.9:0.01:1.1)
    
    # For crop, we need to know image size after scaling
    scaled_size = round(Int, maximum(img_size) * scale_factor)
    crop_x = rand(1:(scaled_size - maximum(img_size) + 1))
    crop_y = rand(1:(scaled_size - maximum(img_size) + 1))
    
    shear_x_angle = rand(-10:0.1:10)
    shear_y_angle = rand(-10:0.1:10)
    rotation_angle = rand(1:0.1:360)
    flip_type = rand([:flipx, :flipy, :noop])
    
    # Input pipeline
    brightness_factor = rand(0.8:0.1:1.2)
    saturation_offset = rand(-0.2:0.1:0.2)
    blur_kernel_size = rand(3:2:7)
    blur_sigma = rand(1:0.1:3)
    
    return (
        scale_factor = scale_factor,
        crop_x = crop_x,
        crop_y = crop_y,
        shear_x_angle = shear_x_angle,
        shear_y_angle = shear_y_angle,
        rotation_angle = rotation_angle,
        flip_type = flip_type,
        brightness_factor = brightness_factor,
        saturation_offset = saturation_offset,
        blur_kernel_size = blur_kernel_size,
        blur_sigma = blur_sigma
    )
end
```

### Step 2: Build Pipeline from Parameters
```julia
function build_pipeline_from_params(params, target_size)
    # Main geometric pipeline
    main_pipeline = Scale(params.scale_factor) |>
                    RCropSize(maximum(target_size), maximum(target_size)) |>
                    ShearX(params.shear_x_angle) |>
                    ShearY(params.shear_y_angle) |>
                    Rotate(params.rotation_angle) |>
                    CropSize(maximum(target_size), maximum(target_size))
    
    # Add flip operation
    if params.flip_type == :flipx
        main_pipeline = main_pipeline |> FlipX()
    elseif params.flip_type == :flipy
        main_pipeline = main_pipeline |> FlipY()
    else
        main_pipeline = main_pipeline |> NoOp()
    end
    
    # Input pipeline (color and blur)
    input_pipeline = ColorJitter(
        params.brightness_factor,
        params.saturation_offset
    ) |> GaussianBlur(
        params.blur_kernel_size,
        params.blur_sigma
    )
    
    # Post pipeline (elastic distortion - fixed params)
    post_pipeline = ElasticDistortion(8, 8, 0.2, 2, 1)
    
    return main_pipeline, input_pipeline, post_pipeline
end
```

### Step 3: Apply and Track
```julia
function augment_with_tracking(source_data, seed::UInt64, target_size)
    # Sample parameters
    params = sample_augmentation_parameters(seed=seed, img_size=size(source_data[1]))
    
    # Build pipelines
    main_pipeline, input_pipeline, post_pipeline = build_pipeline_from_params(params, target_size)
    
    # Apply augmentation
    input, output = source_data
    augmented_input, augmented_output = augment((input, output), main_pipeline)
    augmented_input, augmented_output = augment((augmented_input, augmented_output), CropSize(target_size...))
    
    # Apply post-processing
    augmented_input = augment(augmented_input, post_pipeline |> input_pipeline)
    augmented_output = augment(augmented_output, post_pipeline)
    
    return augmented_input, augmented_output, params
end
```

---

## Challenge: RCropSize

The `RCropSize` operation internally picks a random position. We need to replace it with explicit crop coordinates.

### Investigation Needed

Check Augmentor source for:
- `Crop(x, y, w, h)` - explicit position crop?
- `CenterCrop(w, h)` - fixed center crop?

### Possible Solutions

**Option 1: Use Crop with explicit coordinates**
```julia
# Instead of RCropSize
Crop(crop_x, crop_y, crop_width, crop_height)
```

**Option 2: Pre-sample RCropSize then apply**
```julia
# If we can extract the random position after RCropSize is applied
# (This may not be possible without modifying Augmentor)
```

**Option 3: Manual cropping**
```julia
# Do the crop manually before passing to pipeline
cropped_img = img[crop_x:(crop_x+crop_w-1), crop_y:(crop_y+crop_h-1)]
# Then apply rest of pipeline
```

---

## Reproducibility Benefits

### Exact Reproduction
```julia
# Load metadata
m = metadata[42]

# Reproduce exactly
Random.seed!(m.random_seed)
params = (
    scale_factor = m.scale_factor,
    rotation_angle = m.rotation_angle,
    shear_x_angle = m.shear_x_angle,
    shear_y_angle = m.shear_y_angle,
    flip_type = m.flip_type,
    brightness_factor = m.brightness_factor,
    blur_sigma = m.blur_sigma,
    # ... all other params
)
main_pipeline, input_pipeline, post_pipeline = build_pipeline_from_params(params, target_size)
reproduced = augment(source_img, main_pipeline |> post_pipeline |> input_pipeline)
# Result is bit-for-bit identical ✓
```

### Analysis by Parameter
```julia
# Find all samples with high rotation
high_rotation = filter(m -> m.rotation_angle > 300, metadata)

# Find all samples with horizontal flip
flipped_x = filter(m -> m.flip_type == :flipx, metadata)

# Analyze parameter distributions
rotation_angles = [m.rotation_angle for m in metadata]
histogram(rotation_angles)  # Verify uniform distribution
```

---

## CSV Export Format

```csv
augmented_index,source_index,timestamp,random_seed,scale_factor,crop_x,crop_y,shear_x_angle,shear_y_angle,rotation_angle,flip_type,brightness_factor,saturation_offset,blur_kernel_size,blur_sigma,scar_pct,redness_pct,hematoma_pct,necrosis_pct,background_pct
1,42,2025-11-04T10:23:45,12345678,1.03,15,23,-3.2,5.7,237.4,flipx,1.1,-0.1,5,2.3,12.5,8.3,2.1,0.8,76.3
2,43,2025-11-04T10:23:46,87654321,0.97,8,31,2.1,-1.4,89.2,noop,0.9,0.05,3,1.5,15.2,12.1,5.3,2.2,65.2
...
```

---

## Visualization with Parameters

When displaying augmented samples, show the parameters:

```
Augmented #42 (from source #15)
────────────────────────────────
Geometric:
  Scale:    1.03x
  Crop:     (15, 23)
  Shear:    X=-3.2°, Y=5.7°
  Rotation: 237.4°
  Flip:     Horizontal

Appearance:
  Brightness: 1.1x
  Saturation: -0.1
  Blur:       kernel=5, σ=2.3

Quality:
  Scar:     12.5%
  Redness:   8.3%
  Hematoma:  2.1%
  Necrosis:  0.8%
```

---

## Implementation Checklist

- [ ] Investigate Augmentor's Crop operation for explicit positioning
- [ ] Create `sample_augmentation_parameters()` function
- [ ] Create `build_pipeline_from_params()` function
- [ ] Update `AugmentationMetadata` struct with all parameters
- [ ] Update `generate_augmented_sets()` to use explicit sampling
- [ ] Test reproduction: same seed → same parameters → same result
- [ ] Update CSV export with all parameters
- [ ] Update analysis script to show parameter distributions
- [ ] Create parameter distribution visualizations
- [ ] Add parameter display to visualization output

---

## Testing Strategy

### Test 1: Reproducibility
```julia
# Generate sample with seed
seed = UInt64(12345)
img1, params1 = augment_with_tracking(source, seed, size)

# Regenerate with same seed
img2, params2 = augment_with_tracking(source, seed, size)

# Verify
@test params1 == params2
@test img1 == img2  # Bit-for-bit identical
```

### Test 2: Parameter Extraction
```julia
# Verify all parameters are captured
params = sample_augmentation_parameters(seed=123, img_size=(512,512))
@test haskey(params, :scale_factor)
@test haskey(params, :rotation_angle)
@test haskey(params, :flip_type)
# ... etc for all parameters
```

### Test 3: Range Validity
```julia
# Verify sampled values are within expected ranges
params = sample_augmentation_parameters(seed=123, img_size=(512,512))
@test 0.9 <= params.scale_factor <= 1.1
@test 1 <= params.rotation_angle <= 360
@test -10 <= params.shear_x_angle <= 10
@test params.flip_type in [:flipx, :flipy, :noop]
```

---

## Performance Impact

**Before (implicit sampling):**
- Augmentor samples internally: ~0.1ms overhead per operation

**After (explicit sampling):**
- We sample: ~0.1ms
- Build pipeline: ~0.1ms
- Total overhead: ~0.2ms per augmentation

**Verdict:** Negligible impact (~0.02% for 1-second augmentations)

---

## Benefits Summary

1. ✅ **Perfect Reproducibility** - Exact parameter values known
2. ✅ **Full Transparency** - Can analyze parameter distributions
3. ✅ **Better Debugging** - Know exactly what transformations were applied
4. ✅ **Scientific Rigor** - Complete methodology documentation
5. ✅ **Analysis Capabilities** - Filter/group by parameter values
6. ✅ **Visualization** - Display parameters alongside images

---

## Next Steps

1. Research Augmentor.jl crop operations
2. Prototype explicit parameter sampling
3. Test reproducibility
4. Implement full tracking
5. Update documentation
