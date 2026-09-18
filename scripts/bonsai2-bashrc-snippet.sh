# Add to ~/.bashrc (or source this file from it).

# Update BONSAI2_REPO to wherever you clone this repo.

export BONSAI2_REPO="$HOME/lab/bonsai2"

function bonsai2() {
    echo "Running Ternary-Bonsai-2-27B-PTQ1_0 (no CoT)"
    "$BONSAI2_REPO/scripts/run-bonsai2.sh" -rea off -st "$@"
}

function bonsai2-chat() {
    echo "Running Ternary-Bonsai-2-27B-PTQ1_0 (no CoT, chat)"
    "$BONSAI2_REPO/scripts/run-bonsai2.sh" -rea off "$@"
}

function bonsai2-think() {
    echo "Running Ternary-Bonsai-2-27B-PTQ1_0 (with CoT)"
    "$BONSAI2_REPO/scripts/run-bonsai2.sh" -rea on -st "$@"
}

function bonsai2-think-chat() {
    echo "Running Ternary-Bonsai-2-27B-PTQ1_0 (no CoT, chat)"
    "$BONSAI2_REPO/scripts/run-bonsai2.sh" -rea off "$@"
}

