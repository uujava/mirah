package org.mirah.plugin.impl

import mirah.lang.ast.*
import org.mirah.plugin.*
import org.mirah.typer.*
import org.mirah.jvm.mirrors.*
import org.mirah.jvm.types.*
import static org.mirah.jvm.types.JVMTypeUtils.*
import mirah.impl.MirahParser
import org.mirah.macros.Compiler
import org.mirah.tool.MirahArguments
import org.mirah.util.Logger
import java.util.*
import java.io.*
import org.mirah.plugin.impl.javastub.*

# generates optimized Entry methods
class OptimizeEntryPlugin < CompilerPluginAdapter

  def self.initialize
    @@log = Logger.getLogger OptimizeEntryPlugin.class.getName
  end

  def initialize:void
    super('optimize_entry')
  end

  def start(param, context)
    super(param, context)
    @typer = context[Typer]
    @scoper = context[Scoper]
    @parser = context[Compiler]
    type_system = context[MirrorTypeSystem]
    @entryType:JVMType = type_system.loadNamedType("ru.programpark.vector.dao.dsl.UserEntry").peekInferredType
    @attrMetaType:JVMType = type_system.loadNamedType("ru.programpark.vector.dao.metadata.AttrMeta").peekInferredType
    @string:JVMType = type_system.loadNamedType("java.lang.String").peekInferredType
    args = context[MirahArguments]
    read_params param, args
  end

  private def read_params(params:String, args: MirahArguments):void
    if params != nil and params.trim.length > 0
      split_regexp = '\|'
      param_list = ArrayList.new Arrays.asList params.trim.split split_regexp
      @@log.fine "params: '#{param_list}'"
    end
  end

  def on_infer(node)
    class_defs = node.findDescendants { |n| n.kind_of? ClassDefinition }
    class_defs.each do |cdef:ClassDefinition|
      type = @typer.getInferredType(cdef).peekInferredType
      # optimize only subtypes of Entries
      next unless @entryType.assignableFrom(type)
      # do not optimize if user define attrMeta
      next if overwriteAttrMeta(type:MirrorType)
      map = LinkedHashMap.new
      collect_meta(type:JVMType, map)
      method = @parser.quote do
        def attrMeta(name:String):AttrMeta
        end
      end
      case_node = Case.new(LocalAccess.new(SimpleString.new('name')), [], [])
      class_scope = @scoper.getScope(cdef)
      tmp_name = class_scope.temp("$ATTR_META_TMP")
      
      # use temp const to avoid local variable issue when using static block initializer
      add_tmp_const(cdef, tmp_name)
      index = 1
      map.each do |attr_name:String, attr_type:JVMType|
        const_name = class_scope.temp("$ATTR_META")
        add_const_statement(cdef, tmp_name, attr_name, const_name, index)
        add_when_statement(case_node, attr_name, const_name)
        index +=1
      end
      add_default_statement case_node
      method.body.add case_node
      cdef.body.add method
      @typer.inferAll cdef.body
    end
  end

  def collect_meta(type:JVMType, meta:Map, visited:Set = HashSet.new):void
    return unless type.kind_of? MirrorType
    return unless @entryType.assignableFrom(type)
    return if visited.contains(type)
    visited << type
    @@log.info "collect meta from: #{type}"
    from_meta_members type:MirrorType.getAllDeclaredMethods, meta
    collect_meta(type.superclass, meta, visited)
    type.interfaces.each do |iface:TypeFuture|
       itype = iface.peekInferredType       
       next unless @entryType.assignableFrom(type)
       collect_meta(itype:JVMType, meta, visited)
    end
  end

  # TODO warning on redefinition of attribute
  def from_meta_members(members:List, map:Map):void
    collect = []
    members.each do |member:Member|
      if @attrMetaType === member.returnType
        matcher = member.name.match(/__(.*?)_meta/)
        if matcher
          collect << [matcher.group(1), member.declaringClass]
        end
      end
    end
    collect.sort { |a:List, b:List| a[0]:String.compareTo(b[0]:String) }
    collect.each { |item:List| map[item[0]] = item[1] }
  end

  def add_when_statement(caseNode:Case, attr:String, const:String):void
     attrName = SimpleString.new attr
     attrConst = Constant.new(SimpleString.new(const))
     temp_case = @parser.quote do
       case
         when `attrName` then return `attrConst`
       end
     end
     caseNode.clauses.add(temp_case.clauses.get(0))
  end

  def add_default_statement(caseNode:Case):void
    raiseStmt = @parser.quote do
      raise IllegalArgumentException.new "Attribute #{name} not registered for entry: #{self}"
    end
    caseNode.elseBody.add raiseStmt
  end

  def add_tmp_const(cdef:ClassDefinition, constName:String):void
    tmpConst = SimpleString.new constName
    constNode = @parser.quote {
      import ru.programpark.vector.dao.metadata.AttrMeta
      @@`tmpConst` = nil:AttrMeta
    }
    cdef.body.add(constNode)
  end

  def add_const_statement(cdef:ClassDefinition, tmp:String, attr:String, const:String, index:int):void
    tmpConst = SimpleString.new(tmp)
    metaCall = FunctionalCall.new(SimpleString.new("__#{attr}_meta"), [], nil)
    attr_index = Fixnum.new index
    node =  @parser.quote do
      @@`tmpConst` = `metaCall`
      @@`tmpConst`.setFieldIndex(`attr_index`)
      @@`tmpConst`
    end
    attrConst = SimpleString.new const
    cdef.body.add(ConstantAssign.new(attrConst, node, nil, nil, nil))
  end

  def overwriteAttrMeta(type:MirrorType):boolean
    methods = type.getDeclaredMethods("attrMeta")
    methods.any? { |m:Member| m.argumentTypes.size == 1 && m.argumentTypes[0].equals(@string) }
  end
end