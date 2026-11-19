# THE PER-PROCESS RUNNER — a program that evaluates each cell in `tests-process-cells.nix` in its
# OWN evaluator process and asserts on its exit, its printed value and the process's own counters.
#
# ★ WHY A PROGRAM AND NOT A CHECK. A thunk or byte count is evidence only for the evaluator that
# computed it. Inside a build sandbox that evaluator is a derivation input — one drvPath, one count,
# in every CI column (den-hoag-jutgv). As `apps.<system>.tests-process` the cells call the
# `nix-instantiate` on PATH, and gen-harness's `ci --tests-process` runs it in every column of
# `evaluators.yml` (its `process plane (ci --tests-process)` step, keyed on this file's name),
# refusing a program whose closure carries an evaluator — so none may enter it. Locally:
#   nix develop ./ci --command ci --tests-process
#
# ★ THE CELLS: A HELD PARTIAL APPLICATION BUILDS ONE REVERSE INDEX (den-hoag-occ66). The reverse
# doors bind their Θ(n + E) index at the ACCESSOR application, so `concatMap (dependentsOf acc)
# seeds` builds one index for every seed, and the multi-seed cone grows linearly in the entries.
# Bound per target, the same read built one index per seed and grew quadratically. With t_e the
# process's count at e entries, (t32 − t16) / (t16 − t8) must stay under 2.5, on thunks AND on
# bytes (envs + list + sets + values): linear reads 2, quadratic 4. Measured on upstream Nix
# 2.35.6, thunks: 2.00 with the binding at the accessor, 3.59 with it under the target.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      apps.tests-process.program = pkgs.writeShellScriptBin "tests-process" (
        ''
          set -e
          # The tools the body calls, declared rather than ambient — and never an evaluator.
          export PATH=${
            pkgs.lib.makeBinPath [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
            ]
          }:$PATH
          export cells=${./tests-process-cells.nix} libSrc=${../lib}
          export genPreludeSrc=${inputs.gen-prelude}
          TMPDIR=$(mktemp -d) out=$(mktemp)
          export TMPDIR out
          trap 'rm -rf "$TMPDIR" "$out"' EXIT
          cd "$TMPDIR"
          # The evaluator the cells run under, from this process and the binary they call.
          echo "evaluator: $(nix-instantiate --version | sed -n 1p)"
          # A thunk count is defined only for a serial run, so every cell here, all of them counted,
          # carries gen-harness `lib.serialEval`'s options; `evalArm` keys them on NIX_SHOW_STATS.
          # shellcheck disable=SC1091
          source ${inputs.gen-harness.lib.serialEval { inherit pkgs; }}
          serialEvalOptions "$(command -v nix-instantiate)" || {
            echo "tests-process: CONTROL FAILED: the serial options of $(command -v nix-instantiate) could not be resolved" >&2
            exit 2
          }
          echo "tests-process: serial options: ''${SERIAL_EVAL[*]:-(none)}"
        ''
        + ''
          export NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
          ran=0
          die() {
            echo "tests-process: FAILED at cell $1: $2" >&2
            exit 1
          }
          # evalArm <arm>: runs one cell in its own process; leaves rc/val set. The value variable is
          # `val`, never `out`.
          evalArm() {
            rc=0
            val=$(nix-instantiate ''${NIX_SHOW_STATS:+"''${SERIAL_EVAL[@]}"} --eval --strict --readonly-mode \
              --argstr arm "$1" \
              --argstr genPreludeSrc "$genPreludeSrc" \
              --argstr libSrc "$libSrc" \
              "$cells" 2> "$TMPDIR/err") || rc=$?
            ran=$((ran + 1))
          }
          # <arm> <value>: one cell with the evaluator's statistics on, exit 0 and the hand-derived
          # value required. Every count below is read from that ONE stats file.
          statsRun() {
            export NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$TMPDIR/stats"
            rm -f "$TMPDIR/stats"
            evalArm "$1"
            unset NIX_SHOW_STATS NIX_SHOW_STATS_PATH
            [ "$rc" -eq 0 ] || die "$1" "expected exit 0, got $rc: $(cat "$TMPDIR/err")"
            [ "$val" = "$2" ] || die "$1" "expected value $2, got '$val'"
            statArm=$1
          }
          # Zero matches or more than one is a broken instrument, and dies as one — never a zero.
          oneMatch() { # <what> <matches>
            m=$(printf '%s\n' "$2" | grep -c . || true)
            [ "$m" = 1 ] || die "$statArm" "the stats hold $m match(es) for $1, wanted exactly 1: cannot measure"
          }
          topStat() {
            stat=$(tr -d ' \n' < "$TMPDIR/stats" | grep -o "\"$1\":[0-9]*" | cut -d: -f2 || true)
            oneMatch "$1" "$stat"
          }
          nestedStat() {
            obj=$(tr -d ' \n' < "$TMPDIR/stats" | grep -o "\"$1\":{[^{}]*}" || true)
            oneMatch "$1" "$obj"
            stat=$(printf '%s' "$obj" | grep -o "\"$2\":[0-9]*" | cut -d: -f2 || true)
            oneMatch "$1.$2" "$stat"
          }
          # <door>: the arm at e = 8, 16, 32, each answering 2e + 1; leaves c_thunks_<e> and
          # c_bytes_<e> (envs + list + sets + values), and prints them so their spread is visible.
          sized() {
            for e in 8 16 32; do
              statsRun "$1-$e" $((2 * e + 1))
              topStat nrThunks
              eval "c_thunks_$e=$stat"
              b=0
              for o in envs list sets values; do
                nestedStat "$o" bytes
                b=$((b + stat))
              done
              eval "c_bytes_$e=$b"
            done
            echo "$1: thunks $c_thunks_8 $c_thunks_16 $c_thunks_32; bytes $c_bytes_8 $c_bytes_16 $c_bytes_32"
          }
          # <counter>: (c32 − c16) / (c16 − c8) < 2.5.
          linear() {
            eval "a=\$c_$1_8 b=\$c_$1_16 c=\$c_$1_32"
            [ $((2 * (c - b))) -lt $((5 * (b - a))) ]
          }
          for d in cone impact frontier direct; do
            sized "$d"
            linear thunks || die "$d" "thunks grow faster than linear in the seeds: $c_thunks_8 / $c_thunks_16 / $c_thunks_32 (a reverse index built per target)"
            linear bytes || die "$d" "bytes grow faster than linear in the seeds: $c_bytes_8 / $c_bytes_16 / $c_bytes_32 (a reverse index built per target)"
          done
          # The live control: the same cone with the door re-applied per seed builds one index per
          # target, so both counters must read the quadratic class here, or they do not discriminate.
          sized perapp
          linear thunks && die perapp "the control's thunks read linear ($c_thunks_8 / $c_thunks_16 / $c_thunks_32): the counter does not discriminate"
          linear bytes && die perapp "the control's bytes read linear ($c_bytes_8 / $c_bytes_16 / $c_bytes_32): the counter does not discriminate"
          # 0/0 is a false pass: the runner must have executed every cell above.
          [ "$ran" = "15" ] || die runner "expected 15 evaluations, ran $ran"
          echo "tests-process: 15 cells, every exit read unpiped, every count read from its own process" > "$out"
        ''
        + ''
          cat "$out"
        ''
      );
    };
}
