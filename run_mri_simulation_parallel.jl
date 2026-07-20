include("run_mri_simulation.jl")

function main(args)
    output_file = args["output-file"]
    output_file = replace(output_file, ".mat" => "_part_$(args["job-index"]).mat")
    nworkers = args["num-jobs"]
    
    sequence, phantom, sys, method, sim_params = load_simulation_data(args)
    parts = kfoldperm(length(phantom), nworkers)

    println("Data preloaded, starting parallel simulation on worker ", args["job-index"])

    part_phantom = phantom[parts[args["job-index"]]]


    signal_part = simulate(part_phantom, sequence, sys; sim_params)

    println("Saving output to $output_file")
    matwrite(output_file, Dict("raw" => signal_part))
    println("Done!")
end

function stack_signals(args)
    output_files = [replace(args["output-file"], ".mat" => "_part_$i.mat") for i in 1:args["num-jobs"]]
    signals = [matread(f)["raw"] for f in output_files]
    stacked_signal = sum(signals)

    matwrite(args["output-file"], Dict("raw" => stacked_signal))

    for f in output_files
        rm(f)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__

    @add_arg_table s begin
        "--job-index"
            arg_type = Int
            help = "Index of the current job (1-based)"
        "--num-jobs"
            arg_type = Int
            help = "Total number of parallel jobs"
            required = true
        "--stack-signals"
            arg_type = Bool
            default = false
            help = "Whether to stack signals from different jobs into a single output file (replaces normal execution)."
    end

    args = parse_args(s)

    if args["stack-signals"]
        stack_signals(args)
    else
        main(args)
    end
end
