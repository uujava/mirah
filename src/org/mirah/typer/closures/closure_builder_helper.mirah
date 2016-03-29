package org.mirah.typer.closures

import mirah.lang.ast.*
import org.mirah.util.Logger
import java.util.*
import org.mirah.typer.*
import java.io.File
import org.mirah.jvm.mirrors.*

import org.mirah.jvm.mirrors.MirrorTypeSystem

import org.mirah.macros.MacroBuilder

class ClosureBuilderHelper

  def self.initialize:void
    @@log = Logger.getLogger(ClosureBuilderHelper.class.getName)
  end

  attr_reader typer: Typer
  attr_reader types: TypeSystem
  attr_reader macros: MacroBuilder

  def initialize(typer: Typer, macros: MacroBuilder)
    @typer = typer
    @types = typer.type_system
    @scoper = typer.scoper
    @macros = macros
  end

  def insert_into_body enclosing_body: NodeList, node: Node
    enclosing_body.insert(0, node)
  end


  def infer node: Node
    @typer.infer node
  end

  def get_scope block: Node
    @scoper.getScope(block)
  end

  def get_inner_scope(block: Node)
    @scoper.getIntroducedScope(block)
  end

  def void_type? type: ResolvedType
    @types.getVoidType.resolve.equals type
  end

  def void_type? type: TypeFuture
    @types.getVoidType.resolve.equals type.resolve
  end

  def set_parent_scope method: MethodDefinition, parent_scope: Scope
    @scoper.addScope(method).parent = parent_scope
  end

  def find_enclosing_node block: Node
    if block.parent
      # findAncestor includes the start node, so we start with the parent
      block.parent.findAncestor do |node|
        node.kind_of?(MethodDefinition) ||
        node.kind_of?(Script) ||
        node.kind_of?(Block)
      end
    end
  end

  def find_enclosing_method block: Node
    if block.parent
      # findAncestor includes the start node, so we start with the parent
      block.parent.findAncestor do |node|
        node.kind_of?(MethodDefinition) ||
        node.kind_of?(Script)
      end
    end
  end

  def makeTypeName(position: Position, type: ResolvedType)
    Constant.new(position, SimpleString.new(position, type.name))
  end

  def makeSimpleTypeName(position: Position, type: ResolvedType)
    SimpleString.new(position, type.name)
  end

  def makeTypeName(position: Position, type: ClassDefinition)
    Constant.new(position, SimpleString.new(position, type.name.identifier))
  end

  def get_body node: Node
    # TODO create an interface for nodes with bodies
    if node.kind_of?(MethodDefinition)
      node:MethodDefinition.body
    elsif node.kind_of?(Script)
      node:Script.body
    elsif node.kind_of?(Block)
      node:Block.body
    else
      raise "Unknown type for finding a body #{node.getClass}"
    end
  end

  def find_enclosing_body block: Block
    enclosing_node = find_enclosing_node block
    get_body enclosing_node
  end

  def find_enclosing_method_body block: Block
    enclosing_node = find_enclosing_method block
    get_body enclosing_node
  end

  def method_for(iface: ResolvedType): MethodType
    return iface:MethodType if iface.kind_of? MethodType

    methods = types.getAbstractMethods(iface)
    if methods.size == 0
      @@log.warning("No abstract methods in #{iface}")
      raise UnsupportedOperationException, "No abstract methods in #{iface}"
    elsif methods.size > 1
      raise UnsupportedOperationException, "Multiple abstract methods in #{iface}: #{methods}"
    end
    MethodType(methods:List.get(0))
  end

  # Copies MethodDefinition nodes from block to klass.
  def copy_methods(klass: ClassDefinition, block: Block, parent_scope: Scope): void
    block.body_size.times do |i|
      node = block.body(i)
      # TODO warn if there are non method definition nodes
      # they won't be used at all currently--so it'd be nice to note that.
      if node.kind_of?(MethodDefinition)
        cloned = node.clone:MethodDefinition
        set_parent_scope cloned, parent_scope
        klass.body.add(cloned)
      end
    end
  end

  # Returns true if any MethodDefinitions were found.
  def contains_methods(block: Block): boolean
    block.body_size.times do |i|
      node = block.body(i)
      return true if node.kind_of?(MethodDefinition)
    end
    return false
  end

  # Builds MethodDefinitions in klass for the abstract methods in iface.
  def build_and_inject_methods(klass: ClassDefinition, block: Block, iface: ResolvedType, parent_scope: Scope):void
    mtype = method_for(iface)

    methods = build_methods_for mtype, block, parent_scope
    methods.each do |m: Node|
      klass.body.add m
    end
  end

  def build_constructor(klass: ClassDefinition, binding_type_name: Constant): void
    args = Arguments.new(klass.position,
                         [RequiredArgument.new(SimpleString.new('binding'), binding_type_name)],
                         Collections.emptyList,
                         nil,
                         Collections.emptyList,
                         nil)
    body = FieldAssign.new(SimpleString.new('binding'), LocalAccess.new(SimpleString.new('binding')), nil,  nil, nil)
    constructor = ConstructorDefinition.new(SimpleString.new('initialize'), args, SimpleString.new('void'), [body], nil)
    klass.body.add(constructor)
  end

  # Builds an anonymous class.
  def build_class(position: Position, parent_type: ResolvedType, name:String=nil)
    interfaces = if (parent_type && parent_type.isInterface)
                   [makeTypeName(position, parent_type)]
                 else
                   Collections.emptyList
                 end
    superclass = if (parent_type.nil? || parent_type.isInterface)
                   nil
                 else
                   makeTypeName(position, parent_type)
                 end
    constant = nil
    constant = Constant.new(position, SimpleString.new(position, name)) if name
    ClosureDefinition.new(position, constant, superclass, Collections.emptyList, interfaces, nil)
  end

  def build_closure_class block: Block, parent_type: ResolvedType, parent_scope: Scope
    outer_data = OuterData.new block, typer
    klass = build_class(block.position, parent_type, outer_data.temp_name("Closure"))

    enclosing_body  = find_enclosing_body block

    block_scope = get_scope block.body
    @@log.fine "block body scope #{block_scope.getClass} #{block_scope:MirrorScope.capturedLocals}"

    outer_data = OuterData.new(block, typer)
    block_scope = outer_data.block_scope
    @@log.fine "block scope #{block_scope} #{block_scope:MirrorScope.capturedLocals}"
    @@log.fine "parent scope #{parent_scope} #{parent_scope:MirrorScope.capturedLocals}"
    enclosing_scope = get_scope(enclosing_body)
    @@log.fine "enclosing scope #{enclosing_scope} #{enclosing_scope:MirrorScope.capturedLocals}"
    parent_scope.binding_type ||= begin
                                    name = outer_data.temp_name("Binding")
                                    captures = parent_scope:MirrorScope.capturedLocals
                                    @@log.fine("building binding #{name} with captures #{captures}")
                                    binding_klass = build_class(klass.position,
                                                                nil,
                                                                name)
                                    insert_into_body enclosing_body, binding_klass

              # add methods for captures
              # typer doesn't understand unquoted return types yet, perhaps
              # TODO write visitor to replace locals w/ calls to bound locals
             # captures.each do |bound_var: String|
             #   bound_type = parent_scope:MirrorScope.getLocalType(bound_var, block.position).resolve
             #   attr_def = @macros.quote do
             #     attr_accessor `bound_var` => `Constant.new(SimpleString.new(bound_type.name))`
             #   end
             #   binding_klass.body.insert(0, attr_def)
             # end

                                    infer(binding_klass).resolve
                                  end
    binding_type_name = makeTypeName(klass.position, parent_scope.binding_type)

    build_constructor(klass, binding_type_name)


    insert_into_body enclosing_body, klass
    klass
  end

  # builds the method definitios for inserting into the closure class
  def build_methods_for(mtype: MethodType, block: Block, parent_scope: Scope): List #<MethodDefinition>
    methods = []
    name = SimpleString.new(block.position, mtype.name)

    # TODO handle all arg types allowed
    args = if block.arguments
             block.arguments.clone:Arguments
           else
             Arguments.new(block.position, Collections.emptyList, Collections.emptyList, nil, Collections.emptyList, nil)
           end

    while args.required.size < mtype.parameterTypes.size
      arg = RequiredArgument.new(
        block.position, SimpleString.new("arg#{args.required.size}"), nil)
      args.required.add(arg)
    end
    return_type = makeSimpleTypeName(block.position, mtype.returnType)
    block_method = MethodDefinition.new(block.position, name, args, return_type, nil,[])

    closure_scope = ClosureScope(get_inner_scope(block))

    block_method.body = block.body

    m_types= mtype.parameterTypes


    # Add check casts in if the argument has a type
    i=0
    args.required.each do |a: RequiredArgument|
      if a.type
        m_type = m_types[i]:MirrorType
        a_type = types.get(parent_scope, a.type.typeref).resolve
        if !a_type.equals(m_type) # && m_type:BaseType.assignableFrom(a_type) # could do this, then it'd only add the checkcast if it will fail...
          block_method.body.insert(0,
            Cast.new(a.position,
              Constant.new(SimpleString.new(m_type.name)), LocalAccess.new(a.position, a.name))
            )
        end
      end
      i+=1
    end

    method_scope = MethodScope.new(closure_scope,block_method)
#   @scoper.setScope(block_method,method_scope)

    methods.add(block_method)

    # create a bridge method if necessary
    requires_bridge = false
    # What I'd like it to look like:
    # args.required.zip(m_types).each do |a, m|
    #   next unless a.type
    #   a_type = @types.get(parent_scope, a.type.typeref)
    #   if a_type != m
    #     requires_bridge = true
    #     break
    #   end
    # end
    i=0
    args.required.each do |a: RequiredArgument|
      if a.type
        m_type = m_types[i]:MirrorType
        a_type = types.get(parent_scope, a.type.typeref).resolve
        if !a_type.equals(m_type) # && m_type:BaseType.assignableFrom(a_type)
          @@log.fine("#{name} requires bridge method because declared type: #{a_type} != iface type: #{m_type}")
          requires_bridge = true
          break
        end
      end
      i+=1
    end

    if requires_bridge
      # Copy args without type information so that the normal iface lookup will happen
      # for the args with types args, add a cast to the arg for the call
      bridge_args = Arguments.new(args.position, [], Collections.emptyList, nil, Collections.emptyList, nil)
      call = FunctionalCall.new(name, [], nil)
      args.required.each do |a: RequiredArgument|
        bridge_args.required.add(RequiredArgument.new(a.position, a.name, nil))
        local = LocalAccess.new(a.position, a.name)
        param = if a.type
                  Cast.new(a.position, a.type, local)
                else
                  local
                end
        call.parameters.add param
      end

      bridge_method = MethodDefinition.new(
                        args.position,
                        name,
                        bridge_args,
                        return_type,
                        [call],      # body
                        [],          # annotations
                        [Modifier.new(args.position, 'BRIDGE')]
                      )
      methods.add(bridge_method)
    end
    methods
  end

end