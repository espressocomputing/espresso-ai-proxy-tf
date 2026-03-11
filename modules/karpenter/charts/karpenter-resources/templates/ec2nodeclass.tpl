apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest
  role: {{ .Values.role | quote }}
  subnetSelectorTerms:
    - tags:
        {{ .Values.discoveryTagKey }}: {{ .Values.discoveryTagValue | quote }}
  securityGroupSelectorTerms:
    - tags:
        {{ .Values.discoveryTagKey }}: {{ .Values.discoveryTagValue | quote }}
  tags:
{{- range $key, $value := .Values.tags }}
    {{ $key }}: {{ $value | quote }}
{{- end }}
