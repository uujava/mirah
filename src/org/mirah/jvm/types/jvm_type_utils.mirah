package org.mirah.jvm.types

import mirah.objectweb.asm.Opcodes
import mirah.objectweb.asm.Type
import mirah.objectweb.asm.Opcodes
import mirah.lang.ast.AnnotationList
import mirah.lang.ast.Annotation
import mirah.lang.ast.HashEntry
import mirah.lang.ast.Array
import mirah.lang.ast.Node
import mirah.lang.ast.EnumDefinition
import mirah.lang.ast.MethodDefinition
import mirah.lang.ast.MacroDefinition
import mirah.lang.ast.Annotated
import mirah.lang.ast.HasModifiers
import mirah.lang.ast.Modifier
import mirah.lang.ast.Identifier
import java.util.logging.Logger
import java.util.logging.Level
import org.mirah.jvm.mirrors.Member
import javax.lang.model.type.TypeKind
import javax.lang.model.type.TypeMirror

class JVMTypeUtils
    # defining initialize in class << self does not work
    def self.initialize
      @@ACCESS = {
        PUBLIC: Opcodes.ACC_PUBLIC,
        PRIVATE: Opcodes.ACC_PRIVATE,
        PROTECTED: Opcodes.ACC_PROTECTED,
        DEFAULT: 0
      }
      @@FLAGS = {
        STATIC: Opcodes.ACC_STATIC,
        FINAL: Opcodes.ACC_FINAL,
        SUPER: Opcodes.ACC_SUPER,
        SYNCHRONIZED: Opcodes.ACC_SYNCHRONIZED,
        VOLATILE: Opcodes.ACC_VOLATILE,
        BRIDGE: Opcodes.ACC_BRIDGE,
        VARARGS: Opcodes.ACC_VARARGS,
        TRANSIENT: Opcodes.ACC_TRANSIENT,
        NATIVE: Opcodes.ACC_NATIVE,
        INTERFACE: Opcodes.ACC_INTERFACE,
        ABSTRACT: Opcodes.ACC_ABSTRACT,
        STRICT: Opcodes.ACC_STRICT,
        SYNTHETIC: Opcodes.ACC_SYNTHETIC,
        ANNOTATION: Opcodes.ACC_ANNOTATION,
        ENUM: Opcodes.ACC_ENUM,
        DEPRECATED: Opcodes.ACC_DEPRECATED
      }
      @@log = Logger.getLogger(JVMTypeUtils.class.getName)
  end

  class << self
    
    def isPrimitive(type:JVMType)
      if type.isError
        return false
      end
      sort = type.getAsmType.getSort
      sort != Type.OBJECT && sort != Type.ARRAY
    end

    def supportBoxing(type:JVMType)
      if type.isError
        return false
      end
      return type.box != nil or type.unbox != nil
    end

    def isEnum(type:JVMType):boolean
      0 != (type.flags & Opcodes.ACC_ENUM)
    end

    def isDeclared(type:JVMType):boolean
      type.kind_of?(TypeMirror) && type:TypeMirror.getKind == TypeKind.DECLARED
    end

    def isInterface(type:JVMType):boolean
      0 != (type.flags & Opcodes.ACC_INTERFACE)
    end

    def isAbstract(type:JVMType):boolean
      0 != (type.flags & Opcodes.ACC_ABSTRACT)
    end

    def isAnnotation(type:JVMType):boolean
      0 != (type.flags & Opcodes.ACC_ANNOTATION)
    end

    def isArray(type:JVMType):boolean
      type.getAsmType.getSort == Type.ARRAY
    end

    def isFinal(type:JVMType)
      if type.isError
        return false
      end
      (type.flags & Opcodes.ACC_FINAL) == Opcodes.ACC_FINAL
    end

    def isStatic(type:JVMType)
      if type.isError
        return false
      end
      (type.flags & Opcodes.ACC_STATIC) == Opcodes.ACC_STATIC
    end

    def isFinal(type:Member)
      (type.flags & Opcodes.ACC_FINAL) == Opcodes.ACC_FINAL
    end

    def isStatic(type:Member)
      (type.flags & Opcodes.ACC_STATIC) == Opcodes.ACC_STATIC
    end

    def isAbstract(type:Member):boolean
      (type.flags & Opcodes.ACC_ABSTRACT) == Opcodes.ACC_ABSTRACT
    end

    def calculateFlags(defaultAccess:int, node:Node):int        

        access = defaultAccess
        flags = 0        
        return defaultAccess unless node

        if HasModifiers.class.isAssignableFrom(node.getClass)           
          modifiers = node:HasModifiers.modifiers
          if modifiers
          modifiers.each do |m: Modifier|
            _access = access_opcode(m.value)
            if _access
                access = _access.intValue
            end
            flag = flag_opcode(m.value)
            if flag
                flags |= flag.intValue
            end
          end 
          end
        end 

        if node.kind_of? EnumDefinition
          flags |= Opcodes.ACC_ENUM
        end

        if node.kind_of? MethodDefinition
          if node:MethodDefinition.arguments.rest
            flags |= Opcodes.ACC_VARARGS
          end
        end

        if node.kind_of? MacroDefinition
          if node:MacroDefinition.arguments.rest
            flags |= Opcodes.ACC_VARARGS
          end
        end

        @@log.fine "calculated flag from modifiers: #{flags} access:#{access}"

        flags | access
    end

    def access_opcode(modifier:String):Integer
      @@ACCESS[modifier]:Integer
    end

    def flag_opcode(modifier:String):Integer
      @@FLAGS[modifier]:Integer
    end

  end
end