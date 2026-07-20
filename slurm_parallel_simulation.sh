#!/bin/bash

PHANTOM_FILE="..."
SEQUENCE_FILE="..."
OUTPUT_FILE="..."
NUM_SLURM_JOBS=4

JOB_ID=$(sbatch --parsable <<EOF
#!/bin/bash
#SBATCH --job-name=parallel_mri_sim
#SBATCH --output=parallel_mri_sim_%A_%a.out
#SBATCH --error=parallel_mri_sim_%A_%a.err
#SBATCH --array=1-${NUM_SLURM_JOBS}
#SBATCH --cpus-per-gpu=8
#SBATCH --gpus=1
#SBATCH --mem=96G

julia --threads=auto --project="$(pwd)" run_mri_simulation_parallel.jl \
    --sequence-file "$SEQUENCE_FILE" \
    --phantom-file "$PHANTOM_FILE" \
    --output-file "$OUTPUT_FILE" \
    --job-index \$SLURM_ARRAY_TASK_ID \
    --num-jobs $NUM_SLURM_JOBS
EOF
)

echo "Submitted array job $JOB_ID"

echo "Monitoring job status, with logs from first job in array."
sleep 10
tail -F parallel_mri_sim_${JOB_ID}_1.err parallel_mri_sim_${JOB_ID}_1.out &

echo "Waiting for array jobs to finish..."

while squeue -j $JOB_ID 2>/dev/null | grep -q $JOB_ID; do
    sleep 10
done

echo "All array jobs finished."

echo "Running final stacking step locally..."

julia --threads=auto --project="$(pwd)" run_mri_simulation_parallel.jl \
    --sequence-file "$SEQUENCE_FILE" \
    --phantom-file "$PHANTOM_FILE" \
    --output-file "$OUTPUT_FILE" \
    --stack-signals true \
    --num-jobs $NUM_SLURM_JOBS
