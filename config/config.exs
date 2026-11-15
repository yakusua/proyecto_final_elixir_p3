import Config

# Carpeta donde se guardan los archivos de texto plano.
config :emergencias, data_dir: "data"

if config_env() == :test do
  config :emergencias, data_dir: Path.join(System.tmp_dir!(), "emergencias_test_data")
  config :logger, level: :warning
end
