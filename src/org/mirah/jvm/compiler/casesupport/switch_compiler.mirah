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
import mirah.lang.ast.Node
import mirah.lang.ast.NodeList
import mirah.lang.ast.Case
import mirah.lang.ast.WhenClause
import org.mirah.jvm.types.JVMType
import static org.mirah.jvm.types.JVMTypeUtils.*
import java.util.List
import org.mirah.jvm.compiler.MethodCompiler
import org.mirah.jvm.compiler.Bytecode
import org.mirah.jvm.compiler.BaseCompiler
import org.mirah.util.Logger

class SwitchCompiler < BaseCompiler
  def self.initialize:void
    @@log = Logger.getLogger(SwitchCompiler.class.getName)
  end

  def initialize(method:MethodCompiler, conditionType: JVMType, targetType:JVMType, builder: Bytecode, caseLevel:int)
    super(method.context)
    @method = method
    @builder = builder
    @targetType = targetType
    @conditionType = conditionType
    @caseLevel = caseLevel
  end

  def defaultNode(node, expression)
    @method.visit(node, expression)
  end

  def compile(node:Case, expression: Object):void
    if node.condition
      bodies = {}
      keys = []

      node.clauses.each do |clause:WhenClause|
        clause.candidates.each do |cond:Node|
          keys << [method.readConstValue(cond), cond, clause.body]
        end
      end

      compiler = getTableCompiler(keys, node)
      if compiler
        compiler.compile(node, expression)
      else
        EqualsCaseCompiler.new(@method, @conditionType, @targetType, @builder).compile(node, expression)
      end
    else
    # compile conditions just as if/elsif/else
      SimpleCaseCompiler.new(@method, @targetType, @builder).compile(node, expression)
    end

    @method.recordPosition(node.position)
  end

  def self.supportSwitch(type_name:String):boolean
    return false unless type_name
    return type_name.equals('java.lang.String') ||
        type_name.equals('int')   ||
        type_name.equals('short') ||
        type_name.equals('byte')  ||
        type_name.equals('char')  ||
        type_name.equals('java.lang.Integer') ||
        type_name.equals('java.lang.Short') ||
        type_name.equals('java.lang.Character') ||
        type_name.equals('java.lang.Byte') ||
        type_name.equals('char')
  end

  def self.supportSwitch(clazz:Class):boolean
    return false unless clazz
    return String.class == clazz || castableToInt(clazz) || EnumValue.class == clazz
  end

  def self.castableToInt(clazz:Class)
    return Integer.class == clazz ||
           Short.class == clazz ||
           Character.class == clazz ||
           Byte.class == clazz
  end

  def getTableCompiler(keys:List, node:Case):TableSwitchCompiler
    return nil unless supportSwitch(@conditionType.name) || isEnum(@conditionType)
    denominator = nil:Object
    keys.each_with_index do |key_data:List, i|
      key = key_data[0] # constantValue - Number, String or EnumValue
      cond = key_data[1]:Node # constant Node
      denominator = if i == 0
        widen(key, key, cond)
      else
        widen(key, denominator, cond)
      end
    end
    unless denominator.nil?
      if castableToInt(denominator.getClass)
        return IntSwitchCompiler.new(@method, @targetType, @conditionType, @builder, keys, node.elseBody)
      elsif String.class == denominator.getClass
        return StringSwitchCompiler.new(@method, @targetType, @builder, keys, node.elseBody, @caseLevel)
      elsif denominator.getClass == EnumValue.class
        return EnumSwitchCompiler.new(@method, @targetType, @conditionType, @builder, keys, node.elseBody)
      end
    end
    reportWarning "Condition keys #{keys} incompatible with table switch condition type: #{@conditionType}", node.position
    return nil
  end

  def widen(v1:Object, v2:Object, cond: Node):Object
    one = v1.nil? ? nil : v1.getClass
    two = v2.nil? ? nil : v2.getClass
    unless one
      reportWarning "constant condition type: #{cond} does not support switch", cond.position
      return nil
    end

    if !supportSwitch(one:Class)
      reportWarning "constant condition type: #{cond} does not support switch", cond.position
      return nil
    end

    return nil unless two

    return v1 if one == two

    if two == String.class
       if String.class == one
         return v1
       else
         reportWarning "not a string constant condition type: #{one}", cond.position
         return nil
       end
    elsif one == EnumValue.class
      if two == EnumValue.class
        if v1:EnumValue.type == v2:EnumValue.type
          return v1
        else
          reportWarning "incompatible key enum types #{v1:EnumValue.type} <=> #{v2:EnumValue.type}", cond.position
          return nil
        end
      else
        reportWarning "not an enum key for condition", cond.position
        return nil
      end
    elsif castableToInt(one)
      return v1
    else
      reportWarning "unsupported constant condition type: #{one}", cond.position
      return nil
    end
  end
end