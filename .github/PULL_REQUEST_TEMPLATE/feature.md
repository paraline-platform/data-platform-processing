## Mô tả thay đổi
<!-- Model nào thay đổi? Schema thay đổi gì? Breaking change không? -->

## Loại thay đổi
- [ ] dbt model mới (staging / marts)
- [ ] Sửa logic SQL hiện có
- [ ] Thêm/sửa schema test (`schema.yml`)
- [ ] Spark job mới / cập nhật
- [ ] Cập nhật dbt dependencies (`packages.yml`)
- [ ] Script (`run-dbt.sh` / `run-spark-job.sh`)

## Breaking changes
- [ ] Thay đổi schema output (rename column, đổi type) → cần notify downstream
- [ ] Full-refresh required → ghi rõ: `./scripts/run-dbt.sh <env> run --full-refresh --select <model>`
- [ ] Spark job thay đổi output path/table

## Test plan
- [ ] `dbt parse` pass
- [ ] `dbt run --select <model>` pass trên dev cluster
- [ ] `dbt test --select <model>` pass
- [ ] Spark job: `./scripts/run-spark-job.sh dev small <job> template` render đúng

## Checklist
- [ ] PR target đúng branch (feature → **stg**)
- [ ] Model có description trong `schema.yml`
- [ ] Thêm dbt test cơ bản (`not_null`, `unique`)
- [ ] Image tag `ghcr.io/paraline-platform/dbt:<branch>-<sha>` build thành công

## Promotion checklist (stg→uat hoặc uat→prd)
- [ ] `dbt test` pass hoàn toàn ở môi trường source
- [ ] Breaking changes đã được notify và downstream đã sẵn sàng
- [ ] Không cần `--full-refresh` ở prod (hoặc đã lên kế hoạch maintenance window)
