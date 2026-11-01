{{/*
Define ports for the pods
*/}}
{{- define "chart.container-port" -}}
{{-  default "8000" .Values.containerPort }}
{{- end }}

{{/*
Define service name
*/}}
{{- define "chart.service-name" -}}
{{-  if .Values.serviceName }}
{{-    .Values.serviceName | lower | trim }}
{{-  else }}
{{-    printf "%s-service" .Release.Name }}
{{-  end }}
{{- end }}

{{/*
Define deployment name
*/}}
{{- define "chart.deployment-name" -}}
{{- printf "%s-deployment-vllm" .Release.Name }}
{{- end }}

{{/*
Define service port
*/}}
{{- define "chart.service-port" -}}
{{-  if .Values.servicePort }}
{{-    .Values.servicePort }}
{{-  else }}
{{-    include "chart.container-port" . }}
{{-  end }}
{{- end }}

{{/*
Define service port name
*/}}
{{- define "chart.service-port-name" -}}
"service-port"
{{- end }}

{{/*
Define container port name
*/}}
{{- define "chart.container-port-name" -}}
"container-port"
{{- end }}

{{/*
Define deployment strategy
*/}}
{{- define "chart.strategy" -}}
strategy:
{{-   if not .Values.deploymentStrategy }}
  rollingUpdate:
    maxSurge: 100%
    maxUnavailable: 0
{{-   else }}
{{      toYaml .Values.deploymentStrategy | indent 2 }}
{{-   end }}
{{- end }}

{{/*
Define additional ports
*/}}
{{- define "chart.extraPorts" }}
{{-   with .Values.extraPorts }}
{{      toYaml . }}
{{-   end }}
{{- end }}

{{/*
Define chart external ConfigMaps and Secrets
*/}}
{{- define "chart.externalConfigs" -}}
{{-   with .Values.externalConfigs -}}
{{      toYaml . }}
{{-   end }}
{{- end }}


{{/*
Define liveness et readiness probes
*/}}
{{- define "chart.probes" -}}
{{-   if .Values.readinessProbe  }}
readinessProbe:
{{-     with .Values.readinessProbe }}
{{-       toYaml . | nindent 2 }}
{{-     end }}
{{-   end }}
{{-   if .Values.livenessProbe  }}
livenessProbe:
{{-     with .Values.livenessProbe }}
{{-       toYaml . | nindent 2 }}
{{-     end }}
{{-   end }}
{{- end }}

{{/*
Define resources. Keep the resource maps intact so vendor-specific device
resources such as gpu.intel.com/xe are passed through unchanged.
*/}}
{{- define "chart.resources" -}}
{{- toYaml .Values.resources -}}
{{- end }}


{{/*
Define User used for the main container
*/}}
{{- define "chart.user" }}
{{-   if .Values.image.runAsUser  }}
runAsUser: 
{{-     with .Values.runAsUser }}
{{-       toYaml . | nindent 2 }}
{{-     end }}
{{-   end }}
{{- end }}


{{- define "chart.extraInitEnv" -}}
- name: S3_ENDPOINT_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-secrets
      key: s3endpoint
- name: S3_BUCKET_NAME
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-secrets
      key: s3bucketname
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-secrets
      key: s3accesskeyid
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-secrets
      key: s3accesskey
{{- if .Values.extraInit.s3modelpath }}
- name: S3_PATH
  value: "{{ .Values.extraInit.s3modelpath }}"
{{- end }}
{{- if hasKey .Values.extraInit "awsEc2MetadataDisabled" }}
- name: AWS_EC2_METADATA_DISABLED
  value: "{{ .Values.extraInit.awsEc2MetadataDisabled }}"
{{- end }}
{{- end }}

{{/*
  Define chart labels
*/}}
{{- define "chart.labels" -}}
{{-   with .Values.labels -}}
{{      toYaml . }}
{{-   end }}
{{- end }}
