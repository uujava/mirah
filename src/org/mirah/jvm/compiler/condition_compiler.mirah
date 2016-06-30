# Copyright (c) 2012 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.compiler

import org.mirah.util.Logger
import mirah.objectweb.asm.Label
import mirah.objectweb.asm.Type
import mirah.objectweb.asm.commons.GeneratorAdapter

import mirah.lang.ast.Node
import org.mirah.jvm.types.MemberKind

class ConditionCompiler < BaseCompiler
  import static org.mirah.jvm.types.JVMTypeUtils.*

  def self.initialize:void
    @@log = Logger.getLogger(ConditionCompiler.class.getName)
    @@NEGATED_OPS = {
      '===' => '!==',
      '!==' => '===',
      '==' => '!=',
      '!=' => '==',
      '<' => '>=',
      '>' => '<=',
      '<=' => '>',
      '>=' => '<'
    }
  end
  def initialize(method:BaseCompiler, node:Node, bytecode:Bytecode)
    super(method.context)
    @method = method
    @bytecode = bytecode
    @negated = false
    @node = node
  end
  
  def negate
    @negated = ! @negated
  end
  
  def compile(node:Node, label:Label)
    visit(node, Boolean.TRUE)
    if @op
      doComparison(label)
    else
      doJump(label)
    end
  end

  def doJump(label:Label)
    if isPrimitive(@type)
      if "boolean".equals(@type.name)
        mode = @negated ? GeneratorAdapter.EQ : GeneratorAdapter.NE
        @bytecode.ifZCmp(mode, label)
      else # Do not allow numeric primitives!
         reportError("Numeric expression is not supported for condition argument", @node.position)
      end
    else
      if @negated
        @bytecode.ifNull(label)
      else
        @bytecode.ifNonNull(label)
      end
    end
  end
  
  def pop_from_stack(typename:String)
    # As of https://docs.oracle.com/javase/specs/jvms/se7/html/jvms-2.html#jvms-2.11.1
    # "double", "long" are Category 2 Computational types, all other types are Category 1 Computation types.
    if "double".equals(typename) || "long".equals(typename)
      @bytecode.pop2
    else
      @bytecode.pop
    end
  end

  def doComparison(label:Label)
    op = @negated ? @@NEGATED_OPS[@op] : @op
    @bytecode.ifCmp(@type.getAsmType, CallCompiler.computeComparisonOp(op:String), @negated, label)
  end
  
  def visitNot(node, expression)
    negate
    visit(node.value, expression)
  end
  
  def visitCall(node, expression)
    raise VerifyError.new "call to #{node.name.identifier}'s block has not been converted to a closure at #{node.position}" if node.block

    call = CallCompiler.new(@method, @bytecode, node.position, node.target, node.name.identifier, node.parameters, getInferredType(node))
    member = call.getMethod
    kind = member.kind
    if MemberKind.COMPARISON_OP == kind
      # TODO optimize comparison with 0, null
      call.compileComparisonValues(member)
      @op = member.name
      @type = member.declaringClass
    elsif MemberKind.IS_NULL == kind
      negate
      @method.visit(node.target, Boolean.TRUE)
      @type = getInferredType(node.target)
    else
      call.compile(true)
      @type = getInferredType(node)
    end
  end
  
  def defaultNode(node, expression)
    @method.visit(node, expression)
    @type = getInferredType(node)
  end
end
