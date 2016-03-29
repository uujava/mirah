package org.mirah.typer.closures

import mirah.lang.ast.*
import org.mirah.typer.*
import java.util.logging.Level
import org.mirah.util.Logger
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
import org.mirah.typer.simple.TypePrinter2
import org.mirah.typer.CallFuture
import org.mirah.typer.BaseTypeFuture
import org.mirah.util.AstFormatter
import org.mirah.util.AstChecker
import org.mirah.util.LazyTypePrinter

# Refactored  unused Non Local Return related code from BetterClosureBuilder
# Note! Using exception approach for handling non local return will definitely have performance issues
# Do not think it should be ever implemented
class NlrClosureBuilder < ClosureBuilderHelper

  def self.initialize: void
    @@log = Logger.getLogger(NlrClosureBuilder.class.getName)
  end

  def initialize(typer: Typer, macros: MacroBuilder)
    super typer, macros
    @todo_closures = LinkedHashMap.new
    @scripts = LinkedHashSet.new
  end

  attr_accessor blockCloneMapOldNew: IdentityHashMap
  attr_accessor blockCloneMapNewOld: IdentityHashMap
  attr_accessor parent_scope_to_binding_name: Map

  def prepare_non_local_return_closure(block: Block, parent_type: ResolvedType): Node
    # generates closure classes, AND an exception type
    # and replaces the closure call with something like this:
    #
    # class MyNonLocalReturn < Throwable
    #   def initialize(return_value:`method return type`); @return_value = return_value; end
    #   def return_value; @return_value; end
    # end
    # begin
    #   call { raise MyNonLocalReturn, `value` }
    # rescue MyNonLocalReturn => e
    #   return e.return_value
    # end
    enclosing_node = find_enclosing_node block
    return_type = if enclosing_node.kind_of? MethodDefinition
                    methodType = infer(enclosing_node)
                    methodType:MethodFuture.returnType
                  elsif enclosing_node.kind_of? Script
                    future = AssignableTypeFuture.new block.position
                    future.assign(infer(enclosing_node), block.position)
                    future
                  end
    nlr_klass = define_nlr_exception block
    block = convert_returns_to_raises block, nlr_klass, return_type
    new_node = nlr_prepare block, parent_type, nlr_klass
    resolved = return_type.resolve

    raise "Unable to determine method return type before generating closure including non local return" unless resolved

    enclosing_body = get_body(enclosing_node)
    node_in_body = block.findAncestor { |node| node.parent.kind_of? NodeList }
    new_call = wrap_with_rescue block, nlr_klass, node_in_body, resolved
    node_in_body.parent.replaceChild node_in_body, new_call

    finish_nlr_exception block, nlr_klass, resolved
    insert_into_body enclosing_body, nlr_klass
    infer(nlr_klass)
    new_node
  end

  def has_non_local_return(block: Block): boolean
    (!contains_methods(block)) && # TODO(nh): fix parser so !_ && _ works
    contains_return(block)
  end

  def define_nlr_exception(block: Block): ClosureDefinition
    outer_data = OuterData.new block, typer
    build_class block.position,
                types.getBaseExceptionType.resolve,
                outer_data.temp_name("NLRException")
  end

  def finish_nlr_exception(block: Node, nlr_klass: ClosureDefinition, return_value_type: ResolvedType)
    value_type_name = makeTypeName(block.position, return_value_type)
    required_constructor_arguments = unless void_type? return_value_type
                                       [RequiredArgument.new(SimpleString.new('return_value'), value_type_name)]
                                     else
                                       Collections.emptyList
                                     end
    args = Arguments.new(block.position,
                         required_constructor_arguments,
                         Collections.emptyList,
                         nil,
                         Collections.emptyList,
                         nil)
    body = unless void_type? return_value_type
             [FieldAssign.new(SimpleString.new('return_value'), LocalAccess.new(SimpleString.new('return_value')), nil, [Modifier.new(block.position, 'PROTECTED')], nil)]
           else
             Collections.emptyList
           end
    constructor = ConstructorDefinition.new(SimpleString.new('initialize'), args, SimpleString.new('void'), body, nil)
    nlr_klass.body.add(constructor)

    unless void_type? return_value_type
      name = SimpleString.new(block.position, 'return_value')
      args = Arguments.new(block.position, Collections.emptyList, Collections.emptyList, nil, Collections.emptyList, nil)
      method = MethodDefinition.new(block.position, name, args, value_type_name, nil, [])
      method.body = NodeList.new
      method.body.add Return.new(block.position, FieldAccess.new(SimpleString.new 'return_value'))

      nlr_klass.body.add method
    end
    nlr_klass
  end

  def nlr_prepare(block: Block, parent_type: ResolvedType, nlr_klass: Node): Node
    parent_scope = get_scope block
    klass = build_closure_class block, parent_type, parent_scope

    build_and_inject_methods(klass, block, parent_type, parent_scope)

    new_closure_call_node(block, klass)
  end

  def wrap_with_rescue block: Node, nlr_klass: ClosureDefinition, call: Node, nlr_return_type: ResolvedType
    return_value = unless void_type? nlr_return_type
      Node(Call.new(block.position,
                      LocalAccess.new(SimpleString.new 'ret_error'),
                      SimpleString.new("return_value"),
                      Collections.emptyList,
                      nil
                      ))
    else
      ImplicitNil.new:Node
    end
    Rescue.new(block.position,
               [call],
               [
                RescueClause.new(
                  block.position,
                  [makeTypeName(block.position, nlr_klass)],
                  SimpleString.new('ret_error'),
                  [  Return.new(block.position, return_value)
                  ]
                )
              ],nil
                )
  end

  def convert_returns_to_raises block: Block, nlr_klass: ClosureDefinition, nlr_return_type: AssignableTypeFuture
    # block = Block(block.clone) # I'd like to do this, but it's ...
    return_nodes(block).each do |_n|
      node = _n:Return

      type = if node.value
               infer(node.value)
             else
               types.getVoidType
             end
      nlr_constructor_args = if void_type?(nlr_return_type) && (types.getImplicitNilType.resolve == type.resolve)
                               Collections.emptyList
                             else
                               [node.value]
                             end
      nlr_return_type.assign type, node.position

      _raise = Raise.new(node.position, [
        Call.new(node.position,
          makeTypeName(node.position, nlr_klass),
          SimpleString.new('new'),
          nlr_constructor_args,
          nil)
        ])
      node.parent.replaceChild node, _raise
    end
    block
  end

  def contains_return block: Node
    !return_nodes(block).isEmpty
  end

  def return_nodes(block: Node): List
    #block.findDescendants { |c| c.kind_of? Return }
    # from findDescendants
    # from commented out code in the parser
    # TODO(nh): put this back in the parser
    finder = DescendentFinder2.new(false, false) { |c| c.kind_of? Return }
    finder.scan(block, nil)
    finder.results
  end

  # Returns true if any MethodDefinitions were found.
  def contains_methods(block: Block): boolean
    block.body_size.times do |i|
      node = block.body(i)
      return true if node.kind_of?(MethodDefinition)
    end
    return false
  end

  def prepare_regular_closure(block: Block, parent_type: ResolvedType): Node
    parent_scope = get_scope block
    klass = build_closure_class block, parent_type, parent_scope
    if contains_methods(block)
      copy_methods(klass, block, parent_scope)
    else
      build_and_inject_methods(klass, block, parent_type, parent_scope)
    end
    new_closure_call_node(block, klass)
  end

  def new_closure_call_node(block: Block, klass: Node): Call
    closure_type = infer(klass)
    target = makeTypeName(block.position, closure_type.resolve)
    Call.new(block.position, target, SimpleString.new("new"), [BindingReference.new], nil)
  end

end