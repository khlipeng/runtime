package kube

import (
	"strings"
)

#App: {
	app: {
		name:    string
		version: string
	}

	config: [Name=string]: string

	containers: [Name=string]: #Container & {
		name: Name

		for n, v in config {
			[
				if strings.HasSuffix(strings.ToUpper(n), "PASSWORD") {
					{env: "\(n)": from: secret: "\(app.name)": "\(n)"}
				},
				{env: "\(n)": from: configMap: "\(app.name)": "\(n)"},
			][0]
		}
	}

	services: [Name=string]: #Service & {
		name: Name
	}

	volumes: [Name=string]: #Volume & {
		name: Name
	}

	type:            ( "Deployment" | "StatefulSet" | "DaemonSet" ) | *"Deployment"
	replicas:        int | *1
	serviceAccount?: #ServiceAccount

	kube: #Spec & {
		if len(config) > 0 {
			for k, v in config {
				[
					if strings.HasSuffix(strings.ToUpper(k), "PASSWORD") {
						{secrets: "\(app.name)-config": stringData: "\(k)": v}
					},
					{configMaps: "\(app.name)-config": data: "\(k)": v},
				][0]
			}
		}

		for name, s in services {
			if (s.expose != _|_) {
				if s.expose.type == "Ingress" {
					ingresses: "\(name)": {
						spec: rules: [{
							host: s.expose.host
							http: paths: [
								for portName, p in s.expose.paths {
									{
										pathType: "Exact"
										path:     p
										backend: service: {
											"name": name
											"port": "name": portName
										}
									}
								},
							]
						}]
					}
				}
			}

			"services": "\(name)": {
				let isNodePort = [
					if (s.expose != _|_ ) if s.expose.type == "NodePort" {true},
					false,
				][0]

				spec: selector: s.selector

				spec: ports: [
					for n, port in s.ports {
						name:       n
						targetPort: n

						[
							if strings.HasPrefix(s.name, "udp") {
								{protocol: "UDP"}
							},
							{protocol: "TCP"},
						][0]

						if port != _|_ {
							{
								"port": port

								if isNodePort {
									"nodePort": port
								}
							}
						}

					},
				]

				if s.clusterIP != _|_ {
					spec: clusterIP: s.clusterIP
				}

				if isNodePort {
					spec: type: "NodePort"
				}
			}
		}

		for _, vol in volumes {
			if vol.source.type == "persistentVolumeClaim" {
				persistentVolumeClaims: "\(vol.source.claimName)": spec: vol.source.spec
			}
			if vol.source.type == "configMap" {
				configMaps: "\(vol.source.name)": vol.source.spec
			}
			if vol.source.type == "secret" {
				secrets: "\(vol.source.name)": vol.source.spec
			}
		}

		"\({
			"Deployment":  "deployments"
			"StatefulSet": "statefulSets"
			"DaemonSet":   "daemonSets"
		}[type])": "\(app.name)": {
			spec: "replicas": replicas

			spec: template: spec: "containers": [
				for _, c in containers {
					(_fromContainer & {
						"container": c
						"volumes":   volumes
					}).kube
				},
			]

			spec: template: spec: "volumes": [
				for n, vol in volumes {
					name: n
					"\(vol.source.type)": {
						for k, v in vol.source if !(k == "type" || k == "spec") {
							"\(k)": v
						}
					}
				},
			]

			if serviceAccount != _|_ {
				spec: template: spec: serviceAccount: app.name
			}
		}

		if serviceAccount != _|_ {
			(_fromServiceAccount & {
				"name":           app.name
				"serviceAccount": serviceAccount
			}).kube
		}
	}
}