[![Elixir CI - Compilation](https://github.com/MaxDac/Privee/actions/workflows/pr-ci.yml/badge.svg)](https://github.com/MaxDac/Privee/actions/workflows/pr-ci.yml) [![Fly Deploy](https://github.com/MaxDac/Privee/actions/workflows/fly.yml/badge.svg)](https://github.com/MaxDac/Privee/actions/workflows/fly.yml)

# Privee
Privee FHL project for Microsoft.

## Codespaces development

The project is configured to be developed using Codespaces. The initial script should be able to install all the dependencies, but the `ElixirLS` extension might require some time to fetch and build up all the dependencies.

## How to start developing with NeoVim

It is possible to use NeoVim with a terminal connection. [This script](./.devcontainer/install-neovim-tooling.sh) will have to be executed manually, then to access in SSH, follow [these instructions](https://github.com/microsoft/vscode-dev-containers/blob/main/script-library/docs/sshd.md#usage-when-this-script-is-already-installed-in-an-image) in Codespaces.

## Setup of the project

In order to start developing the project, it's necessary to install Elixir.

After having installed Elixir and Erlang in the machine, install the Phoenix Framework by executing the following command in the terminal:

```bash
mix local.hex
mix archive.install hex phx_new
```

**Note**: to run the project with a local database, for problems of trusting the emulator local certificate,
it will be necessary to run the dotnet app described below.

To start the application, from the root folder, execute these commands

- Install the required dependencies:
```bash
mix deps.get && mix deps compile
```

- Install Tailwind support
```bash
mix tailwind.install
```

- Run the script to initialise the database with the required collections:
```bash
mix run apps/guilds/priv/seeds.exs
```

- Start the local instance of the application:
```bash
mix phx.server
```

This will start the application, that will listen to the port 4000.

### Local development with Docker

To start development, run the database in a Docker container with this command:

```bash
docker run --name privee-database -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres --restart=unless-stopped -p 5432:5432 -d postgres
```

Also, instead of relying on IDE tools, the PGAdmin tool can be started on Docker to explore the database:

```bash
docker run --name pgadmin -e "PGADMIN_DEFAULT_EMAIL=admin@admin.com" -e "PGADMIN_DEFAULT_PASSWORD=admin" --restart=unless-stopped -p 5050:80 -d dpage/pgadmin4
docker network create --driver bridge pgnetwork
docker network connect pgnetwork pgadmin
docker network connect pgnetwork privee-database
```

## IDE support

The most natural way of developing in Elixir is to use Visual Studio Code with Elixir-LS extension.

There are other extensions that helps with developing the application:

- Phoenix Framework
- Surface: A component based library for Phoenix

## Instruction to install Tailwind in the project
[Instructions](https://tailwindcss.com/docs/guides/phoenix)

## Kubernetes discoverability

Normally, every Erlang instance should be connected to one another manually. The package **libcluster** anyway
offers a way of doing it automatically inside a service pod.

For more information refer the [package information](https://hex.pm/packages/libcluster) and the
[guide to set it up](https://www.poeticoding.com/connecting-elixir-nodes-with-libcluster-locally-and-on-kubernetes/).

There is also an interesting guide in parts on [how to configure Elixir nodes on Kubernetes](https://david-delassus.medium.com/elixir-and-kubernetes-a-love-story-721cc6a5c7d5),
always with **libcluster**.

## Azure configuration

### GitHub Actions CI/CD

#### Login to Azure

To login to Azure, a User-defined Managed Identity has been created with a federated identity, and OpenID Connect
authentication type has been selected; the reason Managed Identity has not been used as an authentication type 
is that it required a **self-hosted** environment, i.e. a VM on Azure.

For more information on how to setup the GitHub Action to work with Azure resources using User-defined Managed Identities,
please refer to the [article of the `azure/login` GitHub Action](https://github.com/marketplace/actions/azure-login#login-with-openid-connect-oidc-recommended).

### AKS configuration

#### SECRET_KEY_BASE

The SECRET_KEY_BASE environment variable required by the Phoenix application is currently being stored as a
Kubernetes secret, and inject as an anvironment variables directly in the Kubernetes deployment file.
This is not optimal, but there is issue #109 addressing this.