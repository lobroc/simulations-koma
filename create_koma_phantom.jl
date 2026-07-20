include("src/utils.jl")
using KomaMRI, Statistics, StatsBase, ImageFiltering, Base.Threads
using FileIO, JLD2, NPZ, ProgressBars, ArgParse

s = ArgParseSettings()
@add_arg_table s begin
    "--data-dir"
    help = "Directory containing simulator data"
    arg_type = String
    required = true

    "--patient-index"
    help = "Index of the patient to process"
    arg_type = Int
    default = 0

    "--deformation-index"
    help = "Index of the deformation to process"
    arg_type = Int
    default = 0

    "--static"
    help = "Use static phantom without deformation"
    arg_type = Bool
    default = false
end

params = parse_args(s)

# Static params
BREATH_LENGTH::Float32 = 5.0 # seconds
spatial_scales = vec([0.16, 0.25, 0.25]) # front-back, top-bottom, left-right dims, in meters

data_dir = params["data-dir"]
patients = readdir(data_dir)

tissue_properties = read_jsonc("../simulator-data/segmentation/mr_tissue_properties.jsonc")

patient_dir = data_dir * "/" * "patient_" * string(params["patient-index"]) * "_deformation_" * string(params["deformation-index"])
patient_files = readdir(patient_dir)

println("Found data, loading from: ", patient_dir)
mesh_t0 = npzread(patient_dir * "/mesh_t0.npy") .|> Float32
deformations = npzread(patient_dir * "/relative_deformations.npy") .|> Float32
t1_vol = npzread(patient_dir * "/t1_volume.npy") .|> Float32
t2_vol = npzread(patient_dir * "/t2_volume.npy") .|> Float32
t2star_vol = npzread(patient_dir * "/t2star_volume.npy") .|> Float32
if ! params["static"]
    relative_deform_fields = npzread(patient_dir * "/interpolated_deform_fields_fixed_bones.npy") .|> Float32
end
proton_density_vol = npzread(patient_dir * "/proton_density_volume.npy") .|> Float32
println("Data loaded successfully.")

# Normalise proton density to [0, 1]
proton_density_vol .-= minimum(proton_density_vol)
proton_d_95 = quantile(vec(proton_density_vol), 0.98) # Exclude outliers to prevent extreme values dominating the scale.
proton_d_95_indices = LinearIndices(proton_density_vol)[proton_density_vol .> proton_d_95]
proton_density_vol[proton_d_95_indices] .= proton_d_95 # Cap
proton_density_vol ./= proton_d_95

# Find indices where == 0
values_in_t1_t2 = ((t1_vol .!= 0) .|| (t2_vol .!= 0) .|| (t2star_vol .!= 0))
lin_inds = LinearIndices(values_in_t1_t2)[values_in_t1_t2]

# Convert relative deformations to Koma format
num_timepoints = size(deformations, 1)
num_points = length(lin_inds)
N = num_points

bone_selector = (vec(t2_vol) .== Float32(tissue_properties["bone"]["T2"])) .& (vec(t1_vol) .== Float32(tissue_properties["bone"]["T1"]))
heart_selector = (vec(t2_vol) .== Float32(tissue_properties["heart_muscle"]["T2"])) .& (vec(t1_vol) .== Float32(tissue_properties["heart_muscle"]["T1"]))

lung_selector = (vec(t2star_vol) .== Float32(tissue_properties["lung"]["T2*"])) .& (vec(t1_vol) .== Float32(tissue_properties["lung"]["T1"]))
lung_selector .|= (vec(t2_vol) .== Float32(tissue_properties["blood"]["T2"])) .& (vec(t1_vol) .== Float32(tissue_properties["blood"]["T1"])) # There is also blood in lungs
lung_selector .|= (vec(t2_vol) .== Float32(tissue_properties["cartilage"]["T2"])) .& (vec(t1_vol) .== Float32(tissue_properties["cartilage"]["T1"])) # Cartilage in airways surrogate signal. Also include.

spatial_scales[1] /= size(t1_vol, 1)
spatial_scales[2] /= size(t1_vol, 2)
spatial_scales[3] /= size(t1_vol, 3)

if ! params["static"]
    relative_deform_fields_flat = Float32.(reshape(vec(relative_deform_fields), (size(relative_deform_fields, 1), prod(size(relative_deform_fields)[2:end-1]), 3)))

    relative_deform_fields_flat = relative_deform_fields_flat[:, lin_inds, :] .|> Float32

    # Define time (periodic, jump from end back to start, because full periodic breath) Assume no hysteresis.
    time_phantom = TimeCurve{Float32}(t=[0f0, BREATH_LENGTH], t_unit=[0f0, 1.0f0], periodic=true)

    particle_trajectories = Motion{Float32}(
        action=Path{Float32}(
            dx = permutedims(relative_deform_fields_flat[:, :, 1], (2, 1)) .* spatial_scales[1], # Converted to scale in meters
            dy = permutedims(relative_deform_fields_flat[:, :, 2], (2, 1)) .* spatial_scales[2],
            dz = permutedims(relative_deform_fields_flat[:, :, 3], (2, 1)) .* spatial_scales[3],
        ),
        time = time_phantom, # in seconds
        spins = AllSpins()
    )
    println("Particle trajectories defined successfully.")
    println(particle_trajectories)
else
    println("Static phantom selected, skipping motion definition.")
    particle_trajectories = NoMotion()
end

index_selector = findall(values_in_t1_t2)

xpos = Float32.(map(t -> t[1], index_selector)) .* spatial_scales[1]
ypos = Float32.(map(t -> t[2], index_selector)) .* spatial_scales[2]
zpos = Float32.(map(t -> t[3], index_selector)) .* spatial_scales[3]

println("Defining phantom with ", N, " points.")
input_phantom = Phantom{Float32}(
    "Custom KomaMRI Phantom",
    (xpos .- median(xpos)) .|> Float32,
    (ypos .- median(ypos)) .|> Float32,
    (zpos .- median(zpos)) .|> Float32,
    (proton_density_vol[index_selector]) .|> Float32, # Relative proton density (unitless, from 0 to 1)
    (t1_vol[index_selector] ./ 1000.0) .|> Float32, # Measurements in seconds (convert from ms)
    (t2_vol[index_selector] ./ 1000.0) .|> Float32,
    (t2star_vol[index_selector] ./ 1000.0) .|> Float32,
    zeros(Float32, N), # rad/s
    zeros(Float32, N),
    zeros(Float32, N),
    zeros(Float32, N),
    particle_trajectories
    )

println("Phantom defined successfully, writing.")
if params["static"]
    phantom_filename = data_dir * "/phantoms/koma_phantom_static_patient_" * string(params["patient-index"]) * ".phantom"
else
    phantom_filename = data_dir * "/phantoms/koma_phantom_dynamic_patient_" * string(params["patient-index"]) * "_deform_" * string(params["deformation-index"]) * ".phantom"
end

write_phantom(input_phantom, phantom_filename)
println("Phantom written to: ", phantom_filename)
