# Copyright (c) 2015 The Mirah project authors. All Rights Reserved.
# All contributing project authors may be found in the NOTICE file.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package org.mirah.plugin

import org.mirah.util.Logger
import org.mirah.tool.MirahArguments
import mirah.lang.ast.Node
import mirah.lang.ast.Script
import java.lang.Iterable
import java.util.Map
import java.util.ServiceLoader
import org.mirah.util.Context

# initialize compiler plugins and calls them at proper compilation step
class CompilerPlugins

  def self.initialize:void
    @@log = Logger.getLogger(CompilerPlugins.class.getName)
  end

  def initialize(context:Context)

    class_loader = context[ClassLoader]
    args = context[MirahArguments]
    plugin_params = parse_plugin_params(args.plugins)
    @@log.fine "plugins params map: #{plugin_params} class_loader: #{class_loader}"
    return unless class_loader
    services = ServiceLoader.load(CompilerPlugin.class, class_loader)
    available = {}
    @plugins = plugins = []
    services:Iterable.each do |plugin: CompilerPlugin|
      available.put plugin.key, plugin
    end

    plugin_params.entrySet.each do |entry|
      plugin = available.get(entry.getKey):CompilerPlugin
      if plugin
        plugin.start(entry.getValue:String, context)
        plugins.add plugin
        @@log.fine "plugin started: #{plugin} params: #{entry.getValue}"
      else
        raise "missing plugin implementation for: " + entry.getKey
      end
    end
  end

  def on_parse(node:Node):void
    @plugins.each do |plugin:CompilerPlugin|
      plugin.on_parse node:Script
    end
  end

  def on_infer(node:Node):void
    @plugins.each do |plugin:CompilerPlugin|
       plugin.on_infer node:Script
    end
  end

  def on_clean(node:Node):void
    @plugins.each do |plugin:CompilerPlugin|
      plugin.on_clean node:Script
    end
  end

  def stop:void
    @plugins.each do |plugin:CompilerPlugin|
      plugin.stop
    end
  end

  # parse plugin string pluginKeyA[:PROPERTY_A][,pluginKeyB[:PROPERTY_B]]
  # return key=>param map
  # raise runtime exception if same key parsed multiple times
  def parse_plugin_params(plugin_string:String)
    result = {}
    return result unless plugin_string
    return result if plugin_string.trim.length == 0
    plugins = plugin_string.split ','
    plugins.each do |v|
      v = v.trim
      delim_index = v.indexOf ':'
      if delim_index > 0 or delim_index == v.length - 1
        old_value = result.put v.substring(0, delim_index), v.substring(delim_index + 1, v.length)
      else
        old_value = result.put v, ""
      end
      if old_value
        raise "multiple plugin keys: #{v}:#{old_value}"
      end
    end
    return result
  end
end