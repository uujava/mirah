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
import mirah.objectweb.asm.commons.TableSwitchGenerator
import mirah.lang.ast.NodeList
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.compiler.Bytecode
import org.mirah.jvm.compiler.MethodCompiler

class BodyGenerator implements TableSwitchGenerator
  def initialize(method: MethodCompiler, builder: Bytecode, bodies: NodeList[], defaultBody:NodeList, targetType: JVMType, expression:Object)
    @bodies = bodies
    @method = method
    @builder = builder
    @defaultBody = defaultBody
    @targetType = targetType
    @expression = expression
  end

  def generateCase(order:int, endCaseLabel:Label):void
    body = @bodies[order]
    @method.compileIfBody(body, @expression, @targetType)
    @builder.goTo endCaseLabel
  end

  def generateDefault:void
    if @defaultBody
      @method.compileIfBody(@defaultBody, @expression, @targetType)
    end
  end

end