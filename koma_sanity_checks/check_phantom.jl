using KomaMRI

ph_file = ARGS[1]
num_spins = length(ARGS) > 1 ? parse(Int, ARGS[2]) : 5000

phantom = read_phantom(ph_file)

print(phantom)
print("\n")

display(plot_phantom_map(phantom, :T1, max_spins=num_spins, time_samples=32))
display(plot_phantom_map(phantom, :T2, max_spins=num_spins, time_samples=32))
display(plot_phantom_map(phantom, :ρ, max_spins=num_spins, time_samples=32))

print("Displaying plot, press ENTER to quit.")
readline()
