class ParserController < ApplicationController
  attr_reader :master_oas_json, :oas_config, :curr_oas

  def copy_obj(obj)
    Marshal.load(Marshal.dump(obj))
  end

  def initialize(master_oas_json, oas_config, curr_oas = {})
    @master_oas_json = copy_obj(master_oas_json)
    @oas_config = copy_obj(oas_config)
    @curr_oas = copy_obj(curr_oas)
  end

  def generate_all
    names_arr = @oas_config.keys
    names_arr.each do |curr_name|
      ParserController.new(@master_oas_json,@oas_config).generate_doc(curr_name)
    end
  end

  def add_general_info
    general_info = copy_obj(master_oas_json)
    general_info.delete("paths")
    general_info_upper = copy_obj(general_info).slice("openapi", "servers", "info", "tags")
    general_info_lower = copy_obj(general_info).slice("externalDocs", "components")
    curr_oas_holder = general_info_upper.merge(@curr_oas).merge(general_info_lower)
    ParserController.new(@master_oas_json,@oas_config,curr_oas_holder)
  end

  #name is in Symbol type
  def add_paths(name)
    if !@curr_oas["paths"].nil?
      raise StandardError, "path already added"
    end
    curr_path_item_objs = {}
    specific_paths = get_specific_path_arr(name) #array of paths in string that the documents wants
    master_path_item_objs = @master_oas_json["paths"]
    specific_paths.each {|path|
      if path.include?("*")
        puts("Adding #{path} for #{name.to_s}")
        path_added_flag = false
        master_path_item_objs.keys.each { |master_path|
          if master_path.include?(path.delete("*"))
            path_added_flag = true
            path_item_obj =  copy_obj({master_path => master_path_item_objs[master_path]})
            puts("Added path #{master_path} for #{name.to_s}")
            curr_path_item_objs.merge!(path_item_obj)
          end
        }
        raise StandardError, "Matser oas does not contain #{path} check if you enter the correct parameter in oas.config" if !path_added_flag
        next
      end
      if master_path_item_objs[path].nil?
        raise StandardError, "Matser oas does not contain #{path} check if you enter the correct parameter in oas.config"
      else
        puts("Added path #{path} for #{name.to_s}" )
        path_item_obj =  copy_obj({path => master_path_item_objs[path]})
        curr_path_item_objs.merge!(path_item_obj)
      end
    }
    curr_path_obj = Hash["paths",curr_path_item_objs]
    curr_oas_holder = copy_obj(@curr_oas).merge!(curr_path_obj)
    ParserController.new(@master_oas_json,@oas_config,curr_oas_holder)
  end

  def process_tag
    curr_tags = []
    @curr_oas["paths"].each_value {|path_item_obj|
      path_item_obj.each_value {|operation_obj|
        raise StandardError, "Missing tags for #{operationObj}" if operation_obj["tags"].nil?
        operation_obj["tags"].each {|tag|
          curr_tags.push(tag) if !curr_tags.include?(tag)
          puts("added " + tag.to_s + " to tags") if !curr_tags.include?(tag)
        }
      }
    }
    #tag obj will initially hold all the tags from master
    raise StandardError, "You can only call this method after add_general_info method" if @curr_oas["tags"].nil?
    tag_objs = copy_obj(@curr_oas["tags"])
    tag_objs.delete_if { |tag|
      delete_flag = ""
      if curr_tags.include? tag["name"]
        delete_flag = false
      elsif !tag["x-traitTag"].nil?
        delete_flag = false
      else
        delete_flag = true
      end
      raise StandardError, "Did not account for extreme case tag: processing #{tag.to_s}" if delete_flag == ""
      delete_flag
    }
    @curr_oas["tags"] = tag_objs
    curr_oas_holder = copy_obj(@curr_oas)
    ParserController.new(@master_oas_json,@oas_config,curr_oas_holder)
  end

  def process_params(name)
    curr_oas = copy_obj(@curr_oas)
    curr_path_item_objs = curr_oas["paths"]
    curr_path_item_objs.each_value {|path_item_obj|
      path_item_obj.each_value { |opperation_obj|
        next if opperation_obj["parameters"].nil?
        opperation_obj["parameters"] = opperation_obj["parameters"].select {|curr_param|
          if curr_param["x-custom-params"] != nil
            if !curr_param["x-custom-params"].include?(name.to_s)
              puts(curr_param["name"].to_s + " deleted from " + name.to_s)
              false
            else
              true
            end
          else
            true
          end
        }
        opperation_obj.delete("parameters") if (opperation_obj["parameters"].nil? || opperation_obj["parameters"].empty?)
      }
    }
    ParserController.new(@master_oas_json,@oas_config,curr_oas)
  end

  def process_requestBody(name)
    curr_oas = copy_obj(@curr_oas)
    curr_path_item_objs = curr_oas["paths"]
    curr_path_item_objs.each_value {|path_item_obj|
      path_item_obj.each_value { |opperation_obj|
        next if opperation_obj["requestBody"].nil?
        raise StandardError, "content hash missing from oas" if opperation_obj["requestBody"]["content"].nil?
        opperation_obj["requestBody"]["content"].each_value { |media_type_value|
          raise StandardError, "schema for media type missing in oas" if media_type_value["schema"].nil?
          schema = media_type_value["schema"]

          ###add custom params requirements
          if schema.has_key?("x-custom-params-requirements")
            cust_params_requirements = schema["x-custom-params-requirements"]
            if cust_params_requirements.keys.include?(name.to_s)
              if schema["required"].nil?
                schema["required"] = []
                schema["required"].push(*cust_params_requirements[name.to_s])
              else
                schema["required"].push(*cust_params_requirements[name.to_s])
              end
              puts("added #{cust_params_requirements[name.to_s]} for #{name.to_s} as custom requirements")
            end
          end

          ###process each property of request body
          raise StandardError, "properties for schema missing in oas" if schema["properties"].nil?
          properties = schema["properties"]
          properties.each { |property_name, property_obj|
            next if property_obj["x-custom-params"].nil?
            if !property_obj["x-custom-params"].include?(name.to_s)
              properties.delete(property_name)
              puts("deleted " + property_name.to_s + " for " + name.to_s )
            end
          }
        }
      }
    }
    ParserController.new(@master_oas_json,@oas_config,curr_oas)
  end



  ### Helpers methods that do not support method chaining. Meant for internal use.

  def generate_file(name)
    path = File.expand_path("../react-page/src/oas_spec") + "/" + name.to_s + ".json"
    file = File.open(path, "w")
    file.puts(JSON.pretty_generate(@curr_oas))
    file.close
  end

  def generate_doc(name)
    add_paths(name).add_general_info.process_tag.process_params(name).process_requestBody(name).generate_file(name)
  end

  def get_doc_names
    names = @oas_config.keys
    raise StandardError, "Empty oas.config" if names.nil? || names.empty?
    names
  end

  #Name is symbol type
  def get_specific_path_arr(name)
    raise StandardError "name of document entered does not match oas.config" if @oas_config[name].nil?
    paths = @oas_config[name][:paths]
    raise StandardError "no paths for #{name}" if paths.nil? || paths.empty?
    paths
  end

end
