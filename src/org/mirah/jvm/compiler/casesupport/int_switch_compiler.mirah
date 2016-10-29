# Copyright (c) 2016 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.compiler.casesupport

import mirah.objectweb.asm.Label
import mirah.objectweb.asm.Type
import mirah.objectweb.asm.commons.TableSwitchGenerator
import mirah.lang.ast.Node
import mirah.lang.ast.NodeList
import mirah.lang.ast.Case
import mirah.lang.ast.WhenClause
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.compiler.MethodCompiler
import org.mirah.jvm.compiler.Bytecode
import org.mirah.jvm.compiler.BaseCompiler
import java.util.List
import java.util.Arrays

class IntSwitchCompiler implements TableSwitchGenerator, TableSwitchCompiler

  def initialize(method:MethodCompiler, targetType:JVMType, conditionType:JVMType, builder: Bytecode, keys:List, defaultBody:NodeList)
    @method = method
    @builder = builder
    @targetType = targetType
    @conditionType = conditionType
    @defaultBody = defaultBody
    @keys = int[keys.size]
    @bodies = {}
    keys.each_with_index do |key_data:List, i:int|
      # could by Byte, Character, Short, Integer - read intValue
      key = if key_data[0].kind_of? Character
        key_data[0]:Character.charValue
      else
        key_data[0]:int
      end
      @keys[i] = key
      body_data = Node[2]
      body_data[0] = key_data[2] # when body
      body_data[1] = key_data[1] # when condition
      @bodies[key] = body_data
    end
    Arrays.sort @keys
    initConstants
  end

  def generateCase(key:int, endCaseLabel:Label):void
    body_data:Node[] = @bodies[key]
    body:NodeList = body_data[0]
    if body
      @method.compileIfBody(body, @expression, @targetType)
    end
    @builder.goTo endCaseLabel
  end

  def generateDefault:void
    if @defaultBody
      @method.compileIfBody(@defaultBody, @expression, @targetType)
    end
  end

  def compile(node:Case, expression:Object):void
    verifyKeys
    @expression = expression
    @method.visit(node.condition, Boolean.TRUE)
    @builder.convertValue(@conditionType, @@int)
    @builder.tableSwitch(@keys, self, false)
  end

  def verifyKeys:void
    prev = 0
    # already sorted
    @keys.each_with_index do |k, i|
      if i == 0
        prev = k
      else
        if prev == k
          body_data = @bodies[k]:Node[]
          @method.reportError "same key value #{k}", body_data[1].position
          return
        end
        prev = k
      end
    end
  end

  def initConstants:void
    unless @@int
      @@int = @method.findType("int")
    end
  end
end