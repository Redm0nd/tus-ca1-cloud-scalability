# TUS CA1: Cloud Scalability & Resilience Investigation

CA1 for *Container Design & Deployment*, MSc Software Design with Cloud Native Computing, TUS (2026/2027).

CloudFormation templates, scripts and k6 load tests used to deploy the Product and Coupon services to AWS (eu-west-1) and test how they scale and recover.

## Layout

```
infra/            CloudFormation templates
scripts/          deploy, seed, test and tear-down scripts (run via make)
experiments/      k6 load tests and database seed
productservice/   supplied Product service
couponservice/    supplied Coupon service
```

## Usage

```bash
make up        # build, deploy, seed, smoke test
make stop      # park the stack
make destroy   # delete everything
```

`make help` lists the other targets.

## Experiment labels

| Report | Label |
|---|---|
| 1 | A |
| 2 | B |
| 3 | C |
| 4 | D |
| 5 | G |
| 6 | L |
| 7 | E |
| 8 | F |
| 9 | J1 |
