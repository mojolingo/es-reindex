## Changelog

+ __0.3.3__: Added `-nm` option [@wader](https://github.com/wader)
+ __0.3.2__: Remove activesupport dependency entirely, handle aliased indices [@waterlink](https://github.com/waterlink)
+ __0.3.1__: Add activesupport dependency since es-reindex uses methods from it.
+ __0.3.0__: Add `:if` and `:unless` callbacks
+ __0.2.1__: [BUGFIX] Improve callback presence check
+ __0.2.0__: Lots of bugfixes, use elasticsearch client gem, add .reindex! method and callbacks
+ __0.1.0__: First gem release
+ __0.0.9__: Gemification, Oj -> MultiJSON
+ __0.0.8__: Optimization in string concat (@nara)
+ __0.0.7__: Document header arguments `_timestamp` and `_ttl` are copied as well
+ __0.0.6__: Document headers in bulks are now assembled and properly JSON dumped
+ __0.0.5__: Merge fix for trailing slash in urls (@ichinco), formatting cleanup
+ __0.0.4__: Force create only, update is optional (@pgaertig)
+ __0.0.3__: Yajl -> Oj
+ __0.0.2__: repated document count comparison
+ __0.0.1__: first revision
