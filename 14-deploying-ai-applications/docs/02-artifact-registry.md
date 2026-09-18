# 2. Artifact Registry

## What Is It? (Plain English)

Artifact Registry is Google Cloud's private storage for container images (and other build artifacts). Think of it as your own private Docker Hub — Cloud Run pulls your image from here, not from your laptop.

## Why It Matters for AI Engineers

Cloud Run can't deploy an image sitting only on your local machine — it needs to pull it from somewhere GCP can reach. This is that somewhere, and it's a short, mostly mechanical topic: create a repo once, then push to it every time you build a new version.

## Key Concepts

| Term | Meaning |
|------|---------|
| **Repository** | A named container within Artifact Registry holding your images |
| **Image Tag** | A label on a specific image version, e.g. `:v1` |
| **`docker push`** | Uploads a locally-built image to a repository |
| **`gcloud auth configure-docker`** | One-time setup letting your local Docker CLI authenticate to Artifact Registry |

## How It Fits Together

```mermaid
flowchart LR
    A["Local image<br/>news-summarizer-local"] -->|docker tag| B["REGION-docker.pkg.dev/PROJECT/REPO/news-summarizer:v1"]
    B -->|docker push| C[Artifact Registry]
    C -->|topic 3| D[Cloud Run pulls from here]
```

## Step-by-Step

**1. Create the repository (one time):**
```bat
gcloud artifacts repositories create %REPO_NAME% ^
  --repository-format=docker ^
  --location=%REGION% ^
  --description="Deploying AI Applications module"
```

**2. Let Docker authenticate to it (one time):**
```bat
gcloud auth configure-docker %REGION%-docker.pkg.dev
```

**3. Tag your local image with the full Artifact Registry path:**
```bat
docker tag news-summarizer-local %REGION%-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%/news-summarizer:v1
```

**4. Push it:**
```bat
docker push %REGION%-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%/news-summarizer:v1
```

**5. Confirm it's there:**
```bat
gcloud artifacts docker images list %REGION%-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%
```

## Common Pitfalls

- Forgetting `gcloud auth configure-docker` — `docker push` will fail with an authentication error.
- Reusing the same tag (`:v1`) for every new build — makes it hard to tell which version is actually deployed; increment it (`:v2`, `:v3`) as you iterate.
- Mismatching the region in the image path versus where the repository was actually created — they must match exactly.
- Building on Apple Silicon (M-series Mac) — a plain `docker build` there produces an `arm64` image, but Cloud Run requires `linux/amd64`. It pushes fine and only fails at deploy time with a confusing "exec format error." Fix: `docker buildx build --platform=linux/amd64 -t <image> --push .` (requires the `docker-buildx` plugin).

## Quick Recap

1. Why can't Cloud Run deploy an image that only exists on your laptop?
2. What does `gcloud auth configure-docker` actually set up?
3. What's the risk of always pushing to the same image tag?
