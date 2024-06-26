package kubepkgtool

import (
	"encoding/json"

	"wagon.octohelm.tech/core"
	"wagon.octohelm.tech/docker"
)

#ApplyToDashboard: {
	kubepkg: #KubePkg

	target: {
		group: string
		env:   string | *"default"
	}

	_files: "/src/kubepkg.json": core.#WriteFile & {
		path:     "kubepkg.json"
		contents: json.Marshal(kubepkg)
	}

	_env: core.#ClientEnv & {
		KUBEPKG_DASHBOARD_ENDPOINT: string | *""
		KUBEPKG_ACCESS_TOKEN:       core.#Secret
		CI_COMMIT_AUTHOR:           string | *""
		CI_COMMIT_TITLE:            string | *""
		CI_COMMIT_SHA:              string | *""
		CI_COMMIT_BRANCH:           string | *""
		CI_COMMIT_TAG:              string | *""
	}

	kubepkg: metadata: annotations:{
		"kubepkg.innoai.tech/commitInfo":"\(_env.CI_COMMIT_AUTHOR)\(_env.CI_COMMIT_TITLE)"
		"kubepkg.innoai.tech/commitID":"\(_env.CI_COMMIT_SHA)"
		"kubepkg.innoai.tech/commitBranch":"\(_env.CI_COMMIT_BRANCH)"
		"kubepkg.innoai.tech/commitTag":"\(_env.CI_COMMIT_TAG)"
	}

	_image: docker.#Pull & {
		source: "alpine/curl"
	}

	_apply: docker.#Run & {
		input: _image.output

		mounts: {
			for p, f in _files {
				"\(p)": core.#Mount & {
					dest:     p
					source:   f.path
					contents: f.output
				}
			}
		}

		env: {
			KUBEPKG_DASHBOARD_ENDPOINT: _env.KUBEPKG_DASHBOARD_ENDPOINT
			KUBEPKG_ACCESS_TOKEN:       _env.KUBEPKG_ACCESS_TOKEN
		}

		always: true
		command: {
			name: "sh"
			flags: "-c": """
			set -eux;
			curl -X PUT \\
				--header "Content-Type: application/json" \\
				--header "Authorization: Bearer ${KUBEPKG_ACCESS_TOKEN}" \\
				--data "@/src/kubepkg.json" \\
				--fail \\
			"${KUBEPKG_DASHBOARD_ENDPOINT}/api/kubepkg-dashboard/v0/groups/\(target.group)/envs/\(target.env)/deployments"
			"""
		}
	}

	output: _apply.output
}
