Advanced syntax coloring support for CMake scripts.

The major feature of this package is to highlighting function
arguments according to their use. For example:

![Example CMake script](doc/demo.png)

CMake, as a programming language, has a very simple syntax.
Unfortunately, this makes it hard to read CMake scripts. CMake
supports function calls, but they may not be nested. In addition,
the functions do not support return values like normal programming
languages, instead a function is capable of setting variables in
the scope of the parent. In other words, a parameter could be
anything like the name of a variable, a keyword, a property, or
even a plain string.

By highlighting each argument, CMake scripts becomes much easier to
read, and also to write.

This package is aware of all built-in CMake functions. In addition,
it allows you to add function signatures for your own functions.

The following is colored:

* Function arguments are colored according to it's use, An argument
  can be colored as a *keyword*, a *variable*, a *property*, or a
  *target*. This package provides information on all built-in CMake
  functions. Information on user-defined functions can be added.

* All function names are colored, however, special functions like
  `if', `while', `function', and `include' are colored using a
  different color.

* The constants `true', `false', `yes', `no', `y', `n', `on', and
  `off'.

* The constructs `${...}', `$ENV{...}', and `$<name:...>'.

* In preprocessor definitions like `-DNAME', `NAME' is colored.

* Comments and quoted strings.


Installation:

Place the file in a directory in Emacs' load path.

Add the following lines to a suitable init file, like ~/.emacs, to
enable this package:

(autoload 'cmake-font-lock-activate "cmake-font-lock" nil t)
(add-hook 'cmake-mode-hook 'cmake-font-lock-activate)

This package is designed to be used together with a major mode for
editing CMake files. Once such package is `cmake-mode.el'
distributed by Kitware, however this package is not dependent upon
or associated with any specific CMake major mode. (Note that the
Kitware package contains rudimentary syntax coloring support.)

Customizing:

In order to perform syntax coloring correctly, this package has to
be aware of the keywords and types of the CMake functions used. To
add information about non-standard CMake function, the following
functions can be used:

`cmake-font-lock-add-keywords' -- Add keyword information:

Adding the list of keywords to a function is a simple way to get
basic coloring correct. For most functions, this is sufficient.
For example:

    (cmake-font-lock-add-keywords
       "my-func" '("FILE" "RESULT" "OTHER"))

`cmake-font-lock-set-signature' -- Set full function type:

Set the signature (the type of the arguments) for a function. For
example:

    (cmake-font-lock-set-signature
       "my-func" '(:var nil :prop) '(("FILE" :file) ("RESULT" :var)))

Custom types:

The signatures of CMake functions provided by this package use a
number of types (see `cmake-font-lock-function-signatures'
for details). However, when adding new signatures, it's possible to
use additional types. In that case, the variable
`cmake-font-lock-argument-kind-face-alist' must be modified
to map the CMake type to a concrete Emacs face. For example:

(cmake-font-lock-set-signature "my_warn" (:warning))
(add-to-list '(:warning . font-lock-warning-face)
             cmake-font-lock-argument-kind-face-alist)


Problems:

* In CMake, function taking expressions, like `if' and `while',
  treat any string as the name of a variable, if one exists. This
  mode fontifies all such as variables, whether or not they
  actually refer to variable. You can quote the arguments to
  fontify them as strings (even though that will not prevent CMake
  from interpreting them as variables).

* Normally, keywords are written explicitly when calling a
  function. However, it is legal to assigning them to a variable,
  which is expanded at the time the function is called. In this
  case, remaining arguments will not be colored correctly. For
  example:

        set(def DEFINITION var2)
        get_directory_property(var1 ${def} my_property)
