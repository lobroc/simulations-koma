include("src/utils.jl")
include("src/UpsamplePhantom.jl")
using CUDA, KomaMRI, MAT, ArgParse

s = ArgParseSettings()
@add_arg_table s begin
    "--sequence-file"
        arg_type = String
        help = "Path to the sequence file (.seq, .seqk)"
    "--phantom-file"
        arg_type = String
        help = "Path to the phantom file (.phantom)"
    "--output-file"
        arg_type = String
        help = "Path to save the output .mat file"
    "--phantom-subsample-factor"
        arg_type = Int
        default = 1
        help = "Factor by which to subsample the phantom (default = no subsampling)"
    "--phantom-upsample-factor"
        arg_type = Int
        default = 1
        help = "Factor by which to upsample the phantom (default = no upsampling)"
    "--time-curve-config"
        arg_type = String
        default=""
        help="Path towards a configuration file to define a more complex time curve for breathing."
end

function load_simulation_data(args::Dict{String,Any})
    sequence_file = args["sequence-file"]
    phantom_file = args["phantom-file"]
    phantom_subsample_factor = args["phantom-subsample-factor"]
    phantom_upsample_factor = args["phantom-upsample-factor"]
    # variable_density_opt = args["variable-density"]

    # Load sequence
    println("Preloading sequence...")
    seq_file_extension = sequence_file[findlast('.', sequence_file)+1:end]
    if seq_file_extension == "seq"
        sequence = read_seq(sequence_file)
    elseif seq_file_extension == "seqk"
        sequence = load_jld(sequence_file, "seq")
    else
        error("Unsupported sequence file format: $seq_file_extension")
    end
    println(sequence)

    println("Preloading phantom...")
    phantom = read_phantom(phantom_file)

    if args["time-curve-config"] != ""
        if isfile(args["time-curve-config"])
            println("Loading time curve configuration from: ", args["time-curve-config"])
            time_curve_config = JSON.parsefile(args["time-curve-config"])
            time_curve_config = Dict(k => f32.(v) for (k, v) in time_curve_config)
            tc = TimeCurve(
                t=time_curve_config["t"],
                t_unit=time_curve_config["t_unit"],
                periodic=true,
                periods=time_curve_config["periods"]
            )
            phantom.motion.time = tc
        else
            error("Time curve configuration file not found: ", args["time-curve-config"])
        end
    end

    println("Data loaded!")

    method = BlochMagnus1() # This is sufficient because sequence has hard pulse events only.

    if phantom_subsample_factor > 1
        println("Subsampling phantom by a factor of $phantom_subsample_factor")
        println("Original phantom size: ", size(phantom)[1])
        phantom = phantom[1:phantom_subsample_factor:size(phantom)[1]]
        phantom.ρ .*= (phantom_subsample_factor^3) # Compensate for subsampling by boosting signal.
        println("New phantom size: ", size(phantom)[1])
    end

    if phantom_upsample_factor > 1
        println("Upsampling phantom by a factor of ", phantom_upsample_factor)
        phantom = upsample(phantom, phantom_upsample_factor)
        println("New phantom size: ", size(phantom)[1])
    end

    sys, sim_params = setup_system()

    return sequence, phantom, sys, method, sim_params
end

function main()
    args = parse_args(s)
    output_file = args["output-file"]
    sequence, phantom, sys, method, sim_params = load_simulation_data(args)
    # Ensure method overrides sim_method in sim_params
    sim_params["sim_method"] = method

    # Run simulation
    println("Running simulation...")
    signal = simulate(phantom, sequence, sys; sim_params)

    println("Saving output to $output_file")
    matwrite(output_file, Dict("raw" => signal))
    println("Done!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
