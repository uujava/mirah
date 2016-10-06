# Copyright (c) 2013-2016 The Mirah project authors. All Rights Reserved.
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

package org.mirah.typer.closures

import mirah.lang.ast.Node
import mirah.lang.ast.Block
import mirah.lang.ast.ClassDefinition
import mirah.lang.ast.StaticMethodDefinition
import mirah.lang.ast.ClosureDefinition
import mirah.lang.ast.SyntheticLambdaDefinition
import mirah.lang.ast.MethodDefinition
import mirah.lang.ast.Script
import org.mirah.util.Logger
import org.mirah.typer.Scope
import org.mirah.typer.Typer
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.mirrors.MirrorType
import org.mirah.jvm.mirrors.MirrorTypeSystem

class OuterData

  @@log = Logger.getLogger OuterData.class.getName

  attr_accessor class_node: Node, #class or script
                class_name: String,
                class_scope: Scope,
                method_node: Node, #class or script outer method or nil
                method_name: String,
                method_scope: Scope,
                block_scope: Scope,
                enclosing_class: Node, #closure or class
                enclosing_class_name: String,
                enclosing_method_node: Node,
                enclosing_method_name: String,
                has_block_parent: boolean

  def initialize(inner_node:Node, typer: Typer):void
    @inner_node = inner_node
    has_block_parent = false
    enclosing_class = nil:Node
    class_node = inner_node.findAncestor do |node|
      if node.kind_of?(ClosureDefinition)
        has_block_parent = true
        enclosing_class = node unless enclosing_class
        return false
      end
      return node.kind_of?(ClassDefinition) or node.kind_of?(Script)
    end
    @has_block_parent = has_block_parent
    @class_node = class_node
    @class_name = class_name @class_node
    @class_scope = typer.scoper.getScope(@class_node)

    @enclosing_class = enclosing_class ? enclosing_class : class_node
    @enclosing_class_name = class_name @enclosing_class

    @enclosing_method_node = inner_node.findAncestor do |node|
       return false unless node.parent
       node.kind_of?(MethodDefinition)
    end

    @enclosing_method_name =  method_name @enclosing_method_node

    @method_node = if @enclosing_method_node
      @enclosing_method_node.findAncestor do |node|
        import org.mirah.util.Comparisons
        return false unless node.parent
        node.kind_of?(MethodDefinition) and Comparisons.areSame(node.parent.parent, class_node)
      end
    else
      nil
    end

    @method_name = method_name @method_node

    # use class scope if plain script - hack?
    @method_scope = if @method_node
      typer.scoper.getScope(@method_node)
    else
      @class_scope
    end

    @block_scope = typer.scoper.getScope(inner_node)
    @typer = typer
  end

  def temp_name(scoped_name: String):String
    @class_scope.temp "#{@enclosing_class_name}$#{@enclosing_method_name}$#{scoped_name}"
  end

  def is_meta:boolean
    @method_node.kind_of? StaticMethodDefinition
  end

  def outer_type:JVMType
    outer_type = JVMType @method_scope.selfType.resolve
    if outer_type.kind_of?(MirrorType)
       outer_type = outer_type:MirrorType.erasure:JVMType
    end
    outer_type
  end

  def self.class_name node:Node
    if node.kind_of? ClassDefinition
      node:ClassDefinition.name.identifier
    else
      @@log.fine "#{node} is not a class"
      MirrorTypeSystem.getMainClassName(node:Script)
    end
  end

  def self.method_name node:Node
     node ? node:MethodDefinition.name.identifier : 'anon'
  end

  def toString:String
    "node:#{@inner_node} outer class: #{@class_node}"
  end
end