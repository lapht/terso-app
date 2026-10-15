#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
audit_script="$script_dir/safety-audit.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/Sources/TersoApp" "$fixture_root/Sources/CoreKit/Safety"
cat > "$fixture_root/Sources/TersoApp/Unsafe.swift" <<'EOF'
import Foundation
try FileManager.default.removeItem(at: URL(fileURLWithPath: "/tmp/example"))
try FileManager.default.trashItem(at: URL(fileURLWithPath: "/tmp/example"), resultingItemURL: nil)
unlink("/tmp/example")
remove("/tmp/example")
system("rm -rf /tmp/example")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/rm")
process.arguments = ["-c", "rm -rf /tmp/example"]
EOF
cat > "$fixture_root/Sources/CoreKit/Safety/Allowed.swift" <<'EOF'
import Foundation
try FileManager.default.removeItem(at: URL(fileURLWithPath: "/tmp/example"))
EOF

if output="$(bash "$audit_script" "$fixture_root" 2>&1)"; then
    printf 'safety audit test: expected the unsafe fixture to fail.\n' >&2
    exit 1
else
    audit_status=$?
fi
if [[ "$audit_status" -ne 1 ]]; then
    printf 'safety audit test: expected exit code 1, got %s:\n%s\n' "$audit_status" "$output" >&2
    exit 1
fi
for line in 2 3 4 5 6 8 9; do
    if [[ "$output" != *"Sources/TersoApp/Unsafe.swift:$line:"* ]]; then
        printf 'safety audit test: expected line %s in output, got:\n%s\n' "$line" "$output" >&2
        exit 1
    fi
done

rm "$fixture_root/Sources/TersoApp/Unsafe.swift"
if ! bash "$audit_script" "$fixture_root"; then
    printf 'safety audit test: expected the clean fixture to pass.\n' >&2
    exit 1
fi

printf 'safety audit test: negative and positive cases passed.\n'
