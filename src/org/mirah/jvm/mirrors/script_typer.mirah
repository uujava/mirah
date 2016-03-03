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

package org.mirah.jvm.mirrors

import org.mirah.util.Logger
import java.util.logging.Level
import javax.tools.DiagnosticListener
import mirah.impl.MirahParser
import mirah.lang.ast.Node
import mirah.lang.ast.Script
import org.mirah.macros.JvmBackend
import org.mirah.typer.Scoper
import org.mirah.typer.TypeSystem
import org.mirah.typer.Typer
import org.mirah.util.Context
import org.mirah.util.MirahDiagnostic
import org.mirah.jvm.compiler.ReportedException
import mirah.lang.ast.StaticMethodDefinition
import mirah.lang.ast.MethodDefinition
import mirah.lang.ast.MacroDefinition

# Used for DashE scripts.
# Scripts body converted to static main method, so non static method
# definitions should be replaced with static one to be accessible in script body
class ScriptTyper < SafeTyper
  def self.initialize:void
    @@log = Logger.getLogger(ScriptTyper.class.getName)
  end

  def initialize(context: Context,
                 types: TypeSystem,
                 scopes: Scoper,
                 jvm_backend: JvmBackend,
                 parser: MirahParser)
    super(context, types, scopes, jvm_backend, parser)
  end

  def visitMethodDefinition(mdef, expression)
    @@log.entering("ScriptTyper", "visitMethodDefinition", mdef)

    if !static_def?(mdef)
      static_mdef = StaticMethodDefinition.new(mdef.position)
      static_mdef.name = mdef.name
      static_mdef.arguments = mdef.arguments
      static_mdef.type = mdef.type
      static_mdef.body = mdef.body
      static_mdef.annotations = mdef.annotations
      mdef.parent.replaceChild(mdef, static_mdef)
      @@log.fine("replace with static: #{mdef} #{static_mdef}")
      super static_mdef, expression
    else
      super
    end
  end

   def visitMacroDefinition(defn, expression)
     if !static_def?(defn)
       static_defn = MacroDefinition.new
       static_defn.isStatic = true
       static_defn.name = defn.name
       static_defn.arguments = defn.arguments
       static_defn.body = defn.body
       static_defn.annotations = defn.annotations
       defn.parent.replaceChild(defn, static_defn)
       super static_defn, expression
     else
       super
     end
   end

   def static_def?(mdef:MethodDefinition):boolean
     mdef.kind_of? StaticMethodDefinition and mdef.parent.parent.kind_of? Script
   end

   def static_def?(mdef:MacroDefinition):boolean
     mdef.isStatic and mdef.parent.parent.kind_of? Script
   end
end