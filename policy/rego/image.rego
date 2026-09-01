# Package policy for container images produced by platform.lib.mkContainer.
#
# Input: a CycloneDX 1.5 SBOM of the image closure.
# Data:  data.packages (policy/data/packages/data.json)
#
# The same policy runs at three points:
#   1. Inside the image derivation  (lib/policy/check-closure.nix)
#   2. In CI                        (conftest test / opa eval)
#   3. At admission                 (Kyverno verifying a cosign attestation)
package platform.image

import rego.v1

# --- 1. Explicitly denied packages -------------------------------------------
# Guardrail, not a gate. Catches the obvious "why is LibreOffice in my API
# container" case with a readable message.

deny contains msg if {
	some c in input.components
	c.name in data.packages.denied
	msg := sprintf("%s@%s is on the denied package list", [c.name, c.version])
}

# --- 2. Nothing that provides a shell ----------------------------------------
# A minimal image should have no interactive surface. If this fires, something
# pulled in a makeWrapper script -- check for $out/bin wrappers in contents.

deny contains msg if {
	some c in input.components
	c.name in data.packages.shell_providers
	msg := sprintf(
		"%s puts a shell in the image; use the published output, not the wrapper in $out/bin",
		[c.name],
	)
}

# --- 3. Allowlist (opt-in) ----------------------------------------------------
# Flip enforce_allowlist once the allowed set is generated from the pinned
# Determinate Secure Packages release rather than maintained by hand.

deny contains msg if {
	data.packages.enforce_allowlist
	some c in input.components
	not c.name in data.packages.allowed
	msg := sprintf("%s@%s is not in the approved package set", [c.name, c.version])
}

# --- 4. Licenses --------------------------------------------------------------
# CycloneDX populates licenses inconsistently. Handle id, name and expression
# or you get silent passes.

license_ids(c) := ids if {
	ids := {id |
		some l in c.licenses
		id := l.license.id
	} | {name |
		some l in c.licenses
		name := l.license.name
	} | {expr |
		some l in c.licenses
		expr := l.expression
	}
}

deny contains msg if {
	some c in input.components
	some id in license_ids(c)
	id in data.packages.forbidden_licenses
	msg := sprintf("%s is %s licensed, which is not permitted in distributed images", [c.name, id])
}

# --- Aggregate ----------------------------------------------------------------

allow if count(deny) == 0

violation_count := count(deny)
