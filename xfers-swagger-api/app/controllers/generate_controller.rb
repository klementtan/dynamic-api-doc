class GenerateController < ApplicationController

  def initialize(url)
    @url = url
  end

  def get_master_json
    @master_oas = HttpController.new(@url).make_request
  end

  def write_file (name, json_file)
    path = "/Users/tandeningklement/Desktop/Parser/xfers-swagger-api/template_oas" + "/" + name +".json"
    file = File.open(path, "w")
    file.puts(json_file)
    file.close
  end

  def generate
    master_oas_json = HttpController.new(@url).make_request

    #Get populated nested hash
    master_oas_paths_json = master_oas_json["paths"]
    split_keys = JsonWHashController.new(master_oas_paths_json).split_keys_arr
    populate_nested_hash =
      JsonWHashController.new(master_oas_paths_json).build_nested_hash(split_keys).populate_nested_hash
    write_file("master_oas_processed", JSON.pretty_generate(populate_nested_hash.get_nested_hash))

    #Generate the individual docs
    master_oas_wo_paths_json = Hash[master_oas_json]
    master_oas_wo_paths_json.delete("paths")
    yaml_path = File.expand_path("config") + "/oas.yml"
    yml = YAML.load(File.read(yaml_path))
    JsonWYamlController.new(yml, master_oas_wo_paths_json, populate_nested_hash).generate_all

  end

end