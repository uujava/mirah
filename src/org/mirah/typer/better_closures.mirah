# Copyright (c) 2012-2014 The Mirah project authors. All Rights Reserved.
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

package org.mirah.typer


import java.util.logging.Level
import java.util.Collections
import java.util.Collection
import java.util.LinkedHashMap
import java.util.IdentityHashMap
import java.util.HashSet
import java.util.LinkedHashSet
import java.util.List
import java.util.Stack
import java.util.Map
import java.util.Map.Entry
import java.util.ArrayList
import java.io.File

import mirah.lang.ast.*

import org.mirah.util.Logger
import org.mirah.jvm.compiler.ProxyCleanup
import org.mirah.jvm.mirrors.MirrorScope
import org.mirah.jvm.mirrors.BaseType
import org.mirah.jvm.mirrors.MirrorType
import org.mirah.jvm.mirrors.MirrorTypeSystem
import org.mirah.jvm.mirrors.MirrorFuture
import org.mirah.jvm.mirrors.MethodScope
import org.mirah.jvm.mirrors.ClosureScope
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.types.JVMTypeUtils
import org.mirah.macros.MacroBuilder
import org.mirah.typer.TypePrinter2
import org.mirah.typer.CallFuture
import org.mirah.typer.BaseTypeFuture
import org.mirah.util.AstFormatter
import org.mirah.util.AstChecker
import org.mirah.util.LazyTypePrinter
import org.mirah.typer.closures.*



# This class transforms a Block into an anonymous class once the Typer has figured out
# the interface to implement (or the abstract superclass).
#
# Note: This is ugly. It depends on the internals of the JVM scope and jvm_bytecode classes,
# and the BindingReference node is a hack. This should really all be cleaned up.


# better idea:
#   add_todo doesn't add blocks + types.
#      it adds Script parents to set of them
#      finish iters over scripts to find block -> type map
#      then does them
class BetterClosureBuilder < ClosureBuilderHelper
  implements ClosureBuilderer

  def self.initialize: void
    @@log = Logger.getLogger(BetterClosureBuilder.class.getName)
  end

  def initialize(typer: Typer, macros: MacroBuilder)
    super(typer, macros)
    @todo_closures = LinkedHashMap.new
    @scripts = LinkedHashSet.new
  end

  attr_accessor blockCloneMapOldNew: IdentityHashMap
  attr_accessor blockCloneMapNewOld: IdentityHashMap
  attr_accessor parent_scope_to_binding_name: Map

  def collect_closures scripts: List
    # returns closures in the reverse order from the scripts
    closures = []
    scripts.each do |s: Script|
      closures.addAll BlockFinder.new(typer, @todo_closures).find(s).entrySet
    end
    Collections.reverse(closures) # from outside to inside
    closures
  end

  def finish
    scripts = ArrayList.new(@scripts)
    Collections.reverse(scripts)

    closures = collect_closures scripts

    closures_to_skip = []

    blockToBindings = LinkedHashMap.new # the list of bindings a block closes over
    bindingLocalNamesToTypes = LinkedHashMap.new

    bindingForBlocks = LinkedHashMap.new # the specific binding for a given block


    self.blockCloneMapOldNew = IdentityHashMap.new
    self.blockCloneMapNewOld = IdentityHashMap.new

    selff = self # TODO rm this after the next release
    closures.each do |entry: Entry|
      block = entry.getKey:Block
      on_clone = BlockCloneListener.new self
      block.whenCloned on_clone
      blockCloneMapOldNew.put(block,block)
      blockCloneMapNewOld.put(block,block)
    end

    self.parent_scope_to_binding_name = {}

    i = 0
    closures.each do |entry: Entry|
      i += 1
      @@log.fine "adjust bindings for block #{entry.getKey} #{entry.getValue} #{i}"
      uncloned_block = entry.getKey:Block
      block = blockCloneMapOldNew.get(uncloned_block):Block
      @@log.fine "#{typer.sourceContent block}"
      enclosing_node = find_enclosing_node(block)
      if enclosing_node.nil?
        # this likely means a macro exists and made things confusing
        # by copying the tree
        @@log.fine "enclosing node was nil, removing  #{entry.getKey} #{entry.getValue} #{i}"
        closures_to_skip.add entry
        next
      end
      @@log.fine "#{typer.sourceContent block}"
      @@log.fine "enclosing node #{enclosing_node}"
      @@log.fine "#{typer.sourceContent enclosing_node}"

      ProxyCleanup.new.scan enclosing_node

      enclosing_b = get_body(enclosing_node)
      if enclosing_b.nil?
        closures_to_skip.add entry
        next
      end
      bindingName = "$b#{i}"
      bindingForBlocks.put uncloned_block, bindingName
      parent_scope = get_scope(block):MirrorScope
      adjuster = BindingAdjuster.new(
        self,
        bindingName,
        parent_scope,
        blockToBindings,
        bindingLocalNamesToTypes)

      adjuster.adjust enclosing_b, block
      @@log.fine("After adjusting: #{AstFormatter.new(scripts.get(0):Node)}")

      AstChecker.maybe_check(scripts)
  
      block = blockCloneMapOldNew.get(entry.getKey):Block
      parent_type = entry.getValue:ResolvedType

      unless get_body(find_enclosing_node(block))
        @@log.fine "  enclosing node was nil, removing  #{entry.getKey} #{entry.getValue} #{i}"
        next
      end
      outer_data = OuterData.new(block, typer)

      closure_name = outer_data.temp_name("Closure")
      closure_klass = build_class(block.position, parent_type, closure_name)

      # build closure class
      constructor_args = []
      constructor_params = []

      binding_list = Collection(blockToBindings.get(uncloned_block)) || Collections.emptyList
      binding_args = binding_list.map do |name: String|
        RequiredArgument.new(SimpleString.new(name), SimpleString.new(ResolvedType(bindingLocalNamesToTypes[name]).name))
      end

      binding_list:Collection = blockToBindings.get(uncloned_block) || Collections.emptyList
      binding_list.each do |name: String|
        constructor_args.add RequiredArgument.new(SimpleString.new(name), SimpleString.new(bindingLocalNamesToTypes[name]:ResolvedType.name))
        constructor_param = if outer_data.has_block_parent && !name.equals(parent_scope_to_binding_name[parent_scope])
          FieldAccess.new(SimpleString.new(name))
        else
          LocalAccess.new(SimpleString.new(name))
        end
        constructor_params.add(constructor_param)
      end

      constructor_body = binding_list.map do |name: String|
        FieldAssign.new(SimpleString.new(name), LocalAccess.new(SimpleString.new(name)), nil, [Modifier.new(closure_klass.position, 'PROTECTED')], nil)
      end

      # pass lambda parameters to constructor
      if block.parent.kind_of?(SyntheticLambdaDefinition)
        lambda_params =  (SyntheticLambdaDefinition block.parent).parameters
        super_params = []

        if lambda_params
          j = 0
          lambda_params.each do |param:Node|
            lambda_arg_type = typer.infer(param).resolve
            lambda_arg = "$lambda_arg"+j
            constructor_args.add RequiredArgument.new(SimpleString.new(lambda_arg), SimpleString.new(lambda_arg_type:ResolvedType.name))
            super_params.add LocalAccess.new(SimpleString.new(lambda_arg))
            constructor_params.add param
            j+=1
          end
          constructor_body.add Super.new(super_params, nil)
        end
      end


      args = Arguments.new(closure_klass.position,
                           constructor_args,
                           Collections.emptyList,
                           nil,
                           Collections.emptyList,
                           nil)

      constructor = ConstructorDefinition.new(
        SimpleString.new('initialize'), args,
        SimpleString.new('void'), constructor_body, nil, nil)
      closure_klass.body.add(constructor)

      enclosing_b  = find_enclosing_body block
      insert_into_body enclosing_b, closure_klass

      block_scope = get_scope block
      if contains_methods(block)
        copy_methods(closure_klass, block, block_scope)
      else
        build_and_inject_methods(closure_klass, block, parent_type, block_scope)
      end

      closure_type = infer(closure_klass) # FIXME: this re-infers also the body of the method (which is the ex-body of the block), which is probably duplicate work.

      target = makeTypeName(block.position, closure_type.resolve)
      new_node = Call.new(
        block.position, target,
        SimpleString.new("new"), 
        constructor_params, nil)


      if block.parent.kind_of?(CallSite)
        parent = block.parent:CallSite
        replace_block_with_closure_in_call parent, block, new_node
      elsif block.parent.kind_of?(SyntheticLambdaDefinition) 
        replace_synthetic_lambda_definiton_with_closure(block.parent:SyntheticLambdaDefinition,new_node)
      else
        raise "Cannot handle parent #{block.parent} of block #{block}."
      end

      @@log.fine "inferring new_node #{new_node}"
      infer new_node
      @@log.fine "inferring enclosing_b #{enclosing_b}"
      infer enclosing_b

      @@log.fine "done with #{enclosing_b}"
      @@log.log(Level.FINE, "Inferred AST: #{enclosing_b.position}\n{0}", AstFormatter.new(enclosing_b))
      @@log.log(Level.FINE, "Inferred types: #{enclosing_b.position}\n{0}", LazyTypePrinter.new(typer, enclosing_b))
      
      if @@log.fine?
        buf = java::io::ByteArrayOutputStream.new
        ps = java::io::PrintStream.new(buf)
        printer = TypePrinter2.new(typer, ps)
        printer.scan(enclosing_b, nil)
        ps.close()
        @@log.fine("Inferred types for expr:\n#{String.new(buf.toByteArray)}")
      end
    end
  end

  def add_todo(block: Block, parent_type: ResolvedType)
    return if parent_type.isError || block.parent.nil?

    rtype = BaseTypeFuture.new(block.position)
    rtype.resolved parent_type

    new_scope = typer.addNestedScope block
    new_scope:ClosureScope.closureType = rtype
    if contains_methods block
      infer block.body
    else
      typer.inferClosureBlock block, method_for(parent_type)
    end

    script = block.findAncestor { |n| n.kind_of? Script }

    @todo_closures[block] = parent_type
    @scripts.add script
  end

  def replace_block_with_closure_in_call(parent: CallSite, block: Block, new_node: Node): void
    if block == parent.block
      parent.block = nil
      parent.parameters.add(new_node)
    else
      new_node.setParent(nil)
      parent.replaceChild(block, new_node)
    end
  end

  def replace_synthetic_lambda_definiton_with_closure(parent: SyntheticLambdaDefinition, new_node: Node): void
    parentparent = parent.parent
    new_node.setParent(nil)
    if parentparent.kind_of?(CallSite) && parentparent:CallSite.target!=parent # then the SyntheticLambdaDefinition is not a child of the CallSite itself, but (most likely?) a child of its arguments. FIXME: It is weird that the parent of a child of X is not X.
      parentparent:CallSite.parameters.replaceChild(parent,new_node)
    else
      parentparent.replaceChild(parent,new_node)
    end
  end
end
