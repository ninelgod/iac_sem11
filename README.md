# Gestor de Préstamos

Sistema de gestión de préstamos bancarios construido con microservicios desplegados en AWS mediante infraestructura como código (Terraform).

---
## Pruebas unitarias

Total: 25 tests (10 usuarios / 9 pagos / 6 reportes).

```bash
cd services/usuarios ; npm install ; npm test
cd services/pagos    ; npm install ; npm test
cd services/reportes ; npm install ; npm test
```

---

## Despliegue de infraestructura (Terraform)


### Secuencia de despliegue

```bash
cd iac

# 1. Inicializar providers y módulos
terraform init

# 2. Revisar el plan
terraform plan

# 3. Aplicar la infraestructura (~10-15 min)
terraform apply

# 4. Subir imágenes Docker a ECR (dispara GitHub Actions)
git push origin main   # build → push :latest → deploy ECS

# 5. Verificar que las tareas ECS están en RUNNING
aws ecs list-tasks --cluster gestorpagosg2-cluster
```

### Destruir la infraestructura

```bash
cd iac
terraform destroy
```

> **Nota:** Aurora tiene `deletion_protection = true`. Antes de destruir, deshabilitar la protección desde la consola de AWS o con un `terraform apply` previo cambiando esa variable.

---