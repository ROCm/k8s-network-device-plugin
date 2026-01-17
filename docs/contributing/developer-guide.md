# Contributing to AMD Network Device Plugin for Kubernetes

Thank you for your interest in contributing to the AMD Network Device Plugin for Kubernetes! We welcome contributions from the community and appreciate your efforts to help improve this project.

## Table of Contents

1. [How We Accept Contributions](#how-we-accept-contributions)
2. [Getting Started](#getting-started)
3. [Development Setup](#development-setup)
4. [Making Changes](#making-changes)
5. [Submitting Pull Requests](#submitting-pull-requests)
6. [Code Review Process](#code-review-process)
7. [Additional Resources](#additional-resources)
8. [License](#license)

## How We Accept Contributions

We warmly accept **external contributions** from the community. Below is an overview of how our contribution process works.

### Contribution Workflow

1. **Submit a Pull Request**
   Fork the repository, make your changes, and submit a pull request with a clear description.

2. **Internal Review**
   Our team reviews the PR and may request changes. We run internal validation and testing to ensure quality and compatibility.

3. **Cherry-Pick & Integration**
   Once approved, contributions are cherry-picked into our internal development branch for final integration.

4. **Release**
   The contribution is included in the next public release.

### Why This Process?

This workflow helps us:

* Maintain code quality and consistency
* Ensure compatibility with internal development branches
* Perform thorough testing before release
* Protect our internal development pipeline
* Credit community contributors in release notes

## Getting Started

### Prerequisites

Before you begin, ensure you have:

* **Git** 2.25+
* **Go** 1.23+ (see `.go-version` or `go.mod`)
* **Docker** (for container builds and testing)
* **Kubernetes** familiarity
* **Make**

### Fork & Clone

1. Fork the repository on GitHub

2. Clone your fork locally:

   ```bash
   git clone https://github.com/<your-username>/k8s-network-device-plugin.git
   cd k8s-network-device-plugin
   ```

3. Add the upstream repository:

   ```bash
   git remote add upstream https://github.com/ROCm/k8s-network-device-plugin.git
   ```

4. Fetch the latest changes:

   ```bash
   git fetch upstream main
   ```

## Development Setup

### Build the Project

```bash
# Build the device plugin binary
make build

# Build Docker image
make image

# Run tests
make test

# Generate code coverage
make coverage
```

### Development Environment

```bash
# Install dependencies
go mod download

# Run linting
make lint

# Format code
make fmt
```

## Making Changes

* Create a feature or fix branch from `main`
* Keep changes focused and minimal
* Follow existing coding and naming conventions
* Add or update tests when applicable

## Submitting Pull Requests

### Before Submitting

1. **Run tests locally**

   ```bash
   make test
   make lint
   ```

2. **Update documentation** if user-facing behavior changes

3. **Add tests** for new features or bug fixes

4. **Format code**

   ```bash
   make fmt
   gofmt -s -w .
   ```

5. **Use clear commit messages**

   ```
   feature: Add RDMA health monitoring

   - Implement RDMA device health checks
   - Add metrics export
   - Include tests

   Closes #123
   ```

### Creating the Pull Request

When opening a PR, include:

* A clear and descriptive title
* Explanation of what and why
* References to related issues (if any)
* Notes on testing performed

## Code Review Process

* **Automated checks** run via GitHub Actions
* **Maintainer review** for correctness, quality, tests, and documentation
* **Feedback** may be requested
* **Approval and merge** once all concerns are addressed

## Additional Resources

* [Kubernetes Device Plugin Documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/)
* [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)
* [Effective Go](https://golang.org/doc/effective_go)
* [SR-IOV Network Device Plugin](https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin)

## License

By contributing to this project, you agree that your contributions will be licensed under the Apache License 2.0. See the [LICENSE](../../LICENSE) file for details.


**Thank you for contributing! We’re excited to see what you build.**

For questions, please open an issue or start a discussion on GitHub.