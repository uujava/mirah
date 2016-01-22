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

package org.mirah.plugin.impl.javastub

import mirah.lang.ast.*
import org.mirah.plugin.*
import org.mirah.typer.*
import org.mirah.jvm.types.JVMType
import static org.mirah.jvm.types.JVMTypeUtils.*
import mirah.impl.MirahParser
import org.mirah.tool.MirahArguments
import org.mirah.util.Logger
import java.util.*
import java.io.*
import org.mirah.plugin.impl.*

class FieldStubWriter < StubWriter

  def self.initialize
    @@log = Logger.getLogger MethodStubWriter.class.getName
  end

  def initialize(plugin:JavaStubPlugin, parent: StubWriter, node:FieldDeclaration)
    super(plugin, parent, node)
    @node = node  # hide superclass field to avoid casts!!!
    @name = @node.name.identifier
  end

  def name
    @name
  end

  # TODO modifier
  def generate:void
    type = JVMType(getInferredType(@node).resolve)
    @@log.fine "node:#{@node} type: #{type}"
    access = 'private'
    flags = []
    _final = false
    process_modifiers(HasModifiers(@node)) do |atype:int, value:String|
      # workaround for PRIVATE and PUBLIC annotations for class constants
      if atype == 0
        access = value.toLowerCase if !'PRIVATE'.equals value
      end
      if atype == 1
        flag_str = value.toLowerCase
        flags.add flag_str
        _final = true if flag_str == 'final'
      end
    end

    @@log.fine "access: #{access} modifier: #{flags}"

    if _final
      writeln StubWriter.TAB, "/** values for constants not implemented */"
    end

    write StubWriter.TAB, access, ' '
    write 'static ' if @node.isStatic
    flags.each { |f| write f, ' ' }
    write type.name, ' ', name()
    write ' = ', default_value(type) if _final
    writeln ";"
  end
end