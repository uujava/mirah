package org.mirah.macros.anno;

import java.lang.annotation.*;

@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface Priority {
    /** Used to override macros from libraries. Higher priority macro will be used */
    int value() default 0;
}
