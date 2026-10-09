# Base of all training fixtures

`overlay/` is copied over a freshly generated `shop-service` (fixtures/fixture-config.yaml) before the fixture's own `overlay/` and `apply.ps1`.
It is a correct, green application (15 tests). Each fixture breaks it in one controlled way and documents the task and the answer in its `expected.md`.

Create a project: `.\scripts\new-fixture.ps1 -Name <fixture>`.
