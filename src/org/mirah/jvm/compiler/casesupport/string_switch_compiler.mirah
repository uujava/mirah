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
import mirah.objectweb.asm.commons.GeneratorAdapter
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

class StringSwitchCompiler implements TableSwitchGenerator, TableSwitchCompiler

  def initialize(method:MethodCompiler, targetType:JVMType, builder: Bytecode, keys:List, defaultBody:NodeList, caseLevel:int)
    @method = method
    @builder = builder
    @targetType = targetType
    @hashes =  {}
    @values =  {}
    @defaultBody = defaultBody
    # safe to reuse locals for the same case level
    @switchConditionLocal ="$sw$cond$#{caseLevel}"
    @switchValueLocal ="$sw$val$#{caseLevel}"
    @bodies = NodeList[keys.size + 1]

    keys.each_with_index do |key_data:List, i:int|
      value = key_data[0]:String
      hashCode = value.hashCode
      valueList:List = @hashes[hashCode]
      unless valueList
        valueList = []
        @hashes[hashCode] = valueList
       else
        @method.reportWarning "string constant has the same hash code for: [#{value}] and #{valueList}", key_data[1]:Node.position
      end
      valueList.add(value) # register value for hashCode
      body_data = Object[2]
      body_data[0] = key_data[1] # when condition
      body_data[1] = i # condition order
      @bodies[i] = key_data[2] # when body
      # if @values[value] = body_data -> ??? ERROR: Internal error in compiler: class java.lang.ArrayIndexOutOfBoundsException  0
      if @values.put(value, body_data)
        @method.reportError "duplicate when condition value #{value}", key_data[1]:Node.position
      end
    end
    initConstants
  end

  # compare strings with same hashCode and push their order to stack or -1 (default)
  def generateCase(hashCode:int, endCaseLabel:Label):void
    values = @hashes[hashCode]:List
    pushes = {}
    values.each do |value:String|
      value_data = @values[value]:Object[]
      @builder.loadLocal(@switchConditionLocal)
      @method.visit(value_data[0]:Node, Boolean.TRUE)
      @builder.invokeVirtual(@@object.getAsmType, @@equals)
      nextLabel = @builder.newLabel
      @builder.ifZCmp(GeneratorAdapter.EQ, nextLabel)
      @builder.push(value_data[1]:int)
      @builder.storeLocal(@switchValueLocal, @@int)
      @builder.goTo endCaseLabel
      @builder.mark nextLabel
    end
    @builder.push(-1)
    @builder.storeLocal(@switchValueLocal, @@int)
    @builder.goTo endCaseLabel
  end

  def generateDefault:void
    @builder.push(-1)
    @builder.storeLocal(@switchValueLocal, @@int)
  end

  def compile(node:Case, expression:Object):void
    keys = int[@hashes.size]
    @hashes.keySet.each_with_index { |hash, i| keys[i] = hash:int }
    Arrays.sort keys
    # push string reference for hashCode call
    @method.visit(node.condition, Boolean.TRUE)
    @builder.storeLocal(@switchConditionLocal, @@object)
    # default value
    @builder.push(-1)
    @builder.storeLocal(@switchValueLocal, @@int)
    nullLabel = @builder.newLabel
    @builder.loadLocal(@switchConditionLocal)
    @builder.ifNull nullLabel
    # string hash code
    @builder.loadLocal(@switchConditionLocal)
    @builder.invokeVirtual(@@object.getAsmType, @@hashCode)
    # generate switch by hash code
    @builder.tableSwitch(keys, self, false)
    @builder.mark nullLabel
    orders = int[@bodies.size - 1] # exclude default
    orders.size.times { |i| orders[i] = i }
    @builder.loadLocal(@switchValueLocal)
    # here we have -1(default) or order number for final switch
    @builder.tableSwitch(orders, BodyGenerator.new(@method, @builder, @bodies, @defaultBody, @targetType, expression), true)
  end

  def initConstants:void
    unless @@equals
      @@object = @method.findType("java.lang.String")
      @@int = @method.findType("int")
      @@equalsArgs = [@method.findType("java.lang.Object")]
      @@equals = @method.methodDescriptor(@@object.getMethod("equals", @@equalsArgs))
      @@hashCode = @method.methodDescriptor(@@object.getMethod("hashCode", []))
    end
  end
end