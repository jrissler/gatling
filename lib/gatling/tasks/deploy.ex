defmodule Mix.Tasks.Gatling.Deploy do
  use Mix.Task

  import Gatling.Bash

  @moduledoc """
  - Create a release of git HEAD using Exrm
  - Create a init script for the app so it will reboot on a server reboot
  - Configure Nginx go serve it
  - Start the app
  """

  @shortdoc "Create an exrm release of the given project and deploy it"

  def run([project]) do
    deploy(project)
  end

  def deploy(project) do
    Gatling.env(project)
    |> mix_deps_get()
    |> mix_compile()
    |> mix_digest()
    |> mix_release()
    |> make_deploy_dir()
    |> copy_release_to_deploy()
    |> expand_release()
    |> install_nginx_site()
    |> install_init_script()
    |> mix_ecto_setup()
    |> start_service()
  end

  def mix_deps_get(env) do
    bash("mix", ~w[deps.get], cd: env.build_dir)
    env
  end

  def mix_compile(env) do
    bash("mix", ~w[compile --force], cd: env.build_dir)
    env
  end

  def mix_digest(env) do
    bash("mix", ~w[phoenix.digest -o public/static], cd: env.build_dir)
    env
  end

  def mix_release(env) do
    bash("mix", ~w[release --no-confirm-missing],cd: env.build_dir)
    env
  end

  def make_deploy_dir(env) do
    File.mkdir_p!(env.deploy_dir)
    env
  end

  def copy_release_to_deploy(env) do
    File.cp!(env.built_release_path, env.deploy_path)
    env
  end

  def expand_release(env) do
    bash("tar", ~w[-xf #{env.project}.tar.gz], cd: env.deploy_dir )
    env
  end

  def install_init_script(env) do
    File.write!(env.etc_path, env.script_template)
    File.chmod!(env.etc_path, 0o777)
    bash("update-rc.d", ~w[#{env.project} defaults])
    env
  end

  def install_nginx_site(%{nginx_available_path: available, nginx_enabled_path: enabled} = env) do
    if env.domains do
      File.write!(available, env.nginx_template)
      unless File.exists?(enabled), do: File.ln_s(available, enabled)
      bash("nginx", ~w[-s reload])
    end
    env
  end

  def mix_ecto_setup(env) do
    if Enum.find(env.available_tasks, fn(task)-> task == "ecto.create" end) do
      bash("mix", ~w[do ecto.create, ecto.migrate, run priv/repo/seeds.exs], cd: env.build_dir)
    end
    env
  end

  def start_service(env) do
    bash("service", ~w[#{env.project} start], env: [{"PORT", to_string(env.available_port)}])
    env
  end

end
