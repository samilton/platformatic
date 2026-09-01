package platform.image_test

import data.platform.image
import rego.v1

# Scope the mock to data.packages, not all of data -- replacing the whole
# document makes every test rule appear recursive.
pkg_data := {
	"denied": ["libreoffice", "firefox"],
	"shell_providers": ["bash", "bash-interactive", "coreutils"],
	"forbidden_licenses": ["AGPL-3.0-only"],
	"allowed": ["glibc", "openssl"],
	"enforce_allowlist": false,
}

sbom(components) := {"bomFormat": "CycloneDX", "components": components}

test_clean_image_allowed if {
	image.allow with input as sbom([
		{"name": "glibc", "version": "2.40-36"},
		{"name": "openssl", "version": "3.4.0"},
	])
		with data.packages as pkg_data
}

test_denied_package_blocked if {
	count(image.deny) == 1 with input as sbom([
		{"name": "glibc", "version": "2.40-36"},
		{"name": "libreoffice", "version": "24.8.4.2"},
	])
		with data.packages as pkg_data
}

test_shell_in_closure_blocked if {
	count(image.deny) == 1 with input as sbom([{"name": "bash", "version": "5.2p37"}])
		with data.packages as pkg_data
}

test_forbidden_license_blocked if {
	count(image.deny) == 1 with input as sbom([{
		"name": "somelib",
		"version": "1.0",
		"licenses": [{"license": {"id": "AGPL-3.0-only"}}],
	}])
		with data.packages as pkg_data
}

test_license_expression_form_also_blocked if {
	count(image.deny) == 1 with input as sbom([{
		"name": "somelib",
		"version": "1.0",
		"licenses": [{"expression": "AGPL-3.0-only"}],
	}])
		with data.packages as pkg_data
}

test_license_name_form_also_blocked if {
	count(image.deny) == 1 with input as sbom([{
		"name": "somelib",
		"version": "1.0",
		"licenses": [{"license": {"name": "AGPL-3.0-only"}}],
	}])
		with data.packages as pkg_data
}

test_allowlist_ignored_when_disabled if {
	image.allow with input as sbom([{"name": "randomlib", "version": "1.0"}])
		with data.packages as pkg_data
}

test_allowlist_blocks_unknown_when_enabled if {
	count(image.deny) == 1 with input as sbom([{"name": "randomlib", "version": "1.0"}])
		with data.packages as object.union(pkg_data, {"enforce_allowlist": true})
}

test_denied_and_unlicensed_both_reported if {
	count(image.deny) == 2 with input as sbom([
		{"name": "libreoffice", "version": "24.8.4.2"},
		{"name": "bash", "version": "5.2p37"},
	])
		with data.packages as pkg_data
}
