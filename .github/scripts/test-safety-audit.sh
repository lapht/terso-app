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

# Second fixture: every module that acts on user files, plus look-alikes of the Safety path.
modules_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root" "$modules_root"' EXIT
modules_dir="$modules_root/Sources/CoreKit/Modules"
mkdir -p "$modules_dir" "$modules_root/Sources/CoreKit/Safety" "$modules_root/Sources/CoreKit/SafetyBypass"
cat > "$modules_dir/DuplicateFinder.swift" <<'EOF'
import Foundation
try FileManager.default.moveItem(at: source, to: destination)
EOF
cat > "$modules_dir/LargeFilesModule.swift" <<'EOF'
import Foundation
_ = try FileManager.default.replaceItemAt(original, withItemAt: replacement)
EOF
cat > "$modules_dir/OldFilesModule.swift" <<'EOF'
import Foundation
rename("/tmp/a", "/tmp/b")
truncate("/tmp/a", 0)
EOF
cat > "$modules_dir/UninstallerModule.swift" <<'EOF'
import Foundation
NSWorkspace.shared.recycle([url]) { _, _ in }
process.arguments = ["mv", "/tmp/a", "/tmp/b"]
EOF
cat > "$modules_root/Sources/CoreKit/SafetyBypass/Sneaky.swift" <<'EOF'
import Foundation
try FileManager.default.removeItem(at: url)
EOF
cat > "$modules_root/Sources/CoreKit/Safety/Allowed.swift" <<'EOF'
import Foundation
try FileManager.default.moveItem(at: source, to: destination)
EOF

if output="$(bash "$audit_script" "$modules_root" 2>&1)"; then
    printf 'safety audit test: expected the module bypass fixtures to fail.\n' >&2
    exit 1
else
    audit_status=$?
fi
if [[ "$audit_status" -ne 1 ]]; then
    printf 'safety audit test: expected exit code 1 for module fixtures, got %s:\n%s\n' "$audit_status" "$output" >&2
    exit 1
fi
for expected in \
    "Sources/CoreKit/Modules/DuplicateFinder.swift:2:" \
    "Sources/CoreKit/Modules/LargeFilesModule.swift:2:" \
    "Sources/CoreKit/Modules/OldFilesModule.swift:2:" \
    "Sources/CoreKit/Modules/OldFilesModule.swift:3:" \
    "Sources/CoreKit/Modules/UninstallerModule.swift:2:" \
    "Sources/CoreKit/Modules/UninstallerModule.swift:3:" \
    "Sources/CoreKit/SafetyBypass/Sneaky.swift:2:"; do
    if [[ "$output" != *"$expected"* ]]; then
        printf 'safety audit test: expected %s in output, got:\n%s\n' "$expected" "$output" >&2
        exit 1
    fi
done
if [[ "$output" == *"Sources/CoreKit/Safety/Allowed.swift"* ]]; then
    printf 'safety audit test: Sources/CoreKit/Safety/ must stay exempt, got:\n%s\n' "$output" >&2
    exit 1
fi

printf 'safety audit test: negative and positive cases passed.\n'
