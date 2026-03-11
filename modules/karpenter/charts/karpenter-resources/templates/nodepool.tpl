apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values:
{{ toYaml .Values.capacityTypes | indent 12 }}
{{- if gt (len .Values.instanceTypes) 0 }}
        - key: node.kubernetes.io/instance-type
          operator: In
          values:
{{ toYaml .Values.instanceTypes | indent 12 }}
{{- end }}
  limits:
    cpu: {{ .Values.cpuLimit | quote }}
    memory: {{ .Values.memoryLimit | quote }}
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
