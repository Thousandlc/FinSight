FinSight AI Gateway — ECS internal deployment (P0-5B1A)

Paths:
  Binary (current): /opt/finsight-ai-gateway/current/finsight-ai-gateway
  Releases:         /opt/finsight-ai-gateway/releases/<version>/  (root:root)
  Environment:      /etc/finsight-ai-gateway/production.env       (root:root 0600)
  systemd unit:     /etc/systemd/system/finsight-ai-gateway.service

Service user: finsight (non-root, execute-only; cannot modify releases/binary)

Logs:
  journalctl -u finsight-ai-gateway -f
  journalctl -u finsight-ai-gateway --since "10 min ago"

Rollback:
  sudo ln -sfn /opt/finsight-ai-gateway/releases/<previous-version> /opt/finsight-ai-gateway/current
  sudo systemctl restart finsight-ai-gateway

SSH alias (recommended on dev machine ~/.ssh/config):
  Host finsight-ecs
      HostName <ECS_PUBLIC_IP>
      User root
      IdentityFile ~/.ssh/<private-key>

SSH tunnel (dev machine → ECS localhost):
  ssh -L 18080:127.0.0.1:8080 finsight-ecs
  curl http://127.0.0.1:18080/health

ICP pending:
  Keep BIND_ADDR=127.0.0.1
  Do not open ECS security group port 8080 to 0.0.0.0/0
