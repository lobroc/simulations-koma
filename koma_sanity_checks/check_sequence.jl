using KomaMRI, FileIO, JLD2

seq_file = ARGS[1]
viz_amount = ARGS[2]

seq_file_extension = seq_file[findlast('.', seq_file)+1:end]
if seq_file_extension == "seq"
    sequence = read_seq(seq_file)
elseif seq_file_extension == "seqk"
    sequence = JLD2.load(FileIO.File{FileIO.DataFormat{:JLD2}}(seq_file), "seq")
else
    error("Unsupported sequence file format: $seq_file_extension")
end

print("Full sequence:\n")
print(sequence)
print("\n")

n_rf_events = sum(sequence.RF.T .!= 0)
n_adc_events = sum(sequence.ADC.N .!= 0)
events_over_time = cumsum(sequence.RF.T .!= 0, dims=2)
truncation_index = findlast(events_over_time .== (n_rf_events - n_adc_events))[2]

print("Sequence with no dummy events:\n")
seq_no_dummy = sequence[truncation_index:end]
print(seq_no_dummy)
print("\n")

subsampled_sequence = sum(map(t -> seq_no_dummy[t], 1:parse(Int, viz_amount)))
print("Subsampled sequence:\n")
print(subsampled_sequence)
print("\n")

display(plot_seq(subsampled_sequence))

display(plot_kspace(subsampled_sequence))

print("Displaying plot, press ENTER to quit.")
readline()
