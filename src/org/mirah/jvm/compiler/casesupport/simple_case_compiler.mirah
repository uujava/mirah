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
import org.mirah.util.Context
import org.mirah.jvm.compiler.MethodCompiler
import org.mirah.jvm.compiler.Bytecode
import org.mirah.jvm.compiler.BaseCompiler
import org.mirah.jvm.compiler.ConditionCompiler

class SimpleCaseCompiler
  def initialize(method:MethodCompiler, targetType:JVMType, builder: Bytecode)
    @method = method
    @builder = builder
    @targetType = targetType
  end

  def compile(node:Case, expression: Object):void
    endCaseLabel = @builder.newLabel

    bodies = {}
    compiler = ConditionCompiler.new(@method, node, @builder)
    node.clauses.each do |clause:WhenClause|
      bodyLabel = @builder.newLabel
      clause.candidates.each do |cond:Node|
        compiler.compile(cond, bodyLabel)
      end
      bodies[bodyLabel] = clause.body
    end
    if node.elseBody
      @method.compileIfBody(node.elseBody, expression, @targetType)
      @builder.goTo endCaseLabel
    end
    bodies.each do |label:Label, body: NodeList|
      @builder.mark(label)
      @method.compileIfBody(body, expression, @targetType)
      @builder.goTo(endCaseLabel)
    end
    @method.recordPosition(node.position, true)
    @builder.mark endCaseLabel
  end

end