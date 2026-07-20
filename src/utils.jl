using JSON, JLD2, FileIO
import KomaMRICore: default_sim_params, Bloch
import KomaMRIBase: Scanner

function load_jld(sequence_file::String, key_name::String)
    return JLD2.load(FileIO.File{FileIO.DataFormat{:JLD2}}(sequence_file), key_name)
end

function strip_json_comments(text::String)
    # Remove // comments
    text = replace(text, r"//.*" => "")
    # Remove /* */ comments
    text = replace(text, r"/\*.*?\*/"s => "")
    return text
end

function read_jsonc(file_path::String)
    raw = read(file_path, String)
    clean = strip_json_comments(raw)
    return JSON.parse(clean)
end

function setup_system(properties_path::String = "scanner_properties.jsonc")
    scanner_properties = read_jsonc(properties_path)

    # Set sim params
    sim_params = default_sim_params()
    sim_params["return_type"] = "mat" # signal values from coil
    sim_params["Nthreads"] = 64
    sim_params["gpu"] = true
    sim_params["precision"] = "f32"
    sim_params["sim_method"] = Bloch()

    sys = Scanner()
    sys.B0 = scanner_properties["B0"]
    # B1 leave unspecified
    sys.Gmax = scanner_properties["max_grad"]
    sys.Smax = scanner_properties["max_slew"] # T/m/s == mT/m/ms
    sys.ADC_Δt = scanner_properties["adc_raster_time"] # s
    sys.DUR_Δt = scanner_properties["block_duration_raster"] # s
    sys.GR_Δt = scanner_properties["grad_raster_time"] # s
    sys.RF_Δt = scanner_properties["rf_raster_time"] # s
    sys.RF_ring_down_time = scanner_properties["rf_ringdown_time"] # s
    sys.RF_dead_time = scanner_properties["rf_dead_time"] # s
    sys.ADC_dead_time = scanner_properties["adc_dead_time"] # s

    return sys, sim_params
end
