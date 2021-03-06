namespace Simple.Web.Links
{
    using System;
    using System.Collections.Generic;
    using System.Collections.ObjectModel;
    using System.Linq;
    using System.Reflection;
    using System.Text;
    using Helpers;

    internal interface ILinkBuilder
    {
        ICollection<Link> LinksForModel(object model);
        Link CanonicalForModel(object model);
    }

    internal class LinkBuilder : ILinkBuilder
    {
        public static readonly ILinkBuilder Empty = new EmptyLinkBuilder();
        private readonly IList<Link> _templates;

        public LinkBuilder(IEnumerable<Link> templates)
        {
            _templates = templates.ToArray();
        }

        public ICollection<Link> LinksForModel(object model)
        {
            var actuals =
                _templates.Select(l => new Link(l.GetHandlerType(), BuildUri(model, l.Href), l.Rel, l.Type, l.Title)).Where(l => l.Href != null).ToList();
            return new ReadOnlyCollection<Link>(actuals);
        }
        
        public Link CanonicalForModel(object model)
        {
            return
                _templates.Where(t => t.Rel == "self").Select(
                    l => new Link(l.GetHandlerType(), BuildUri(model, l.Href), l.Rel, l.Type, l.Title)).FirstOrDefault(l => l.Href != null);
        }

        private static PropertyInfo GetModelProperty(Type modelType, string property)
        {
            return modelType.GetProperty(property) ?? modelType.GetProperties().FirstOrDefault(p => p.Name.Equals(property, StringComparison.OrdinalIgnoreCase));
        }

        private static string BuildUri(object model, string uriTemplate)
        {
            int queryStart = uriTemplate.IndexOf("?", StringComparison.Ordinal);
            var uri = new StringBuilder(uriTemplate);
            var variables = new HashSet<string>(UriTemplateHelper.ExtractVariableNames(uriTemplate),
                                                StringComparer.OrdinalIgnoreCase);
            if (variables.Count > 0)
            {
                foreach (var variable in variables)
                {
                    var prop = GetModelProperty(model.GetType(), variable);
                    if (prop == null)
                    {
                        return null;
                    }
                    var sub = "{" + variable + "}";
                    var v = prop.GetValue(model, null);
                    if (v == null)
                    {
                        return null;
                    }
                    var value = v.ToString();
                    if (queryStart >= 0)
                    {
                        if (uriTemplate.IndexOf(sub, StringComparison.OrdinalIgnoreCase) > queryStart)
                        {
                            value = Uri.EscapeDataString(value);
                        }
                    }
                    uri.Replace(sub, value);
                }
            }
            return uri.ToString();
        }

        private class EmptyLinkBuilder : ILinkBuilder
        {
            private static readonly Link[] EmptyArray = new Link[0];
            public ICollection<Link> LinksForModel(object model)
            {
                return EmptyArray;
            }

            public Link CanonicalForModel(object model)
            {
                return null;
            }
        }
    }
}